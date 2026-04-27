#!/usr/bin/env node

/**
 * SyncWave Web Backend
 * Node.js + Express server for cross-platform audio streaming
 *
 * Runs on port 5005
 * Access from any device on WiFi: http://[server-ip]:5005
 */

const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const dgram = require('dgram');
const { v4: uuidv4 } = require('uuid');
const os = require('os');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Configuration
const PORT = 5005;
const RTP_PORT = 5004;
const MULTICAST_ADDR = '239.0.0.1';

// Device registry
const devices = new Map();
const audioStreams = new Map();

// RTP configuration
let rtpSocket = null;
let currentSender = null;
let sequenceNumber = 0;
let rtpTimestamp = 0;
const SSRC = Math.floor(Math.random() * 0xffffffff);

// ============================================
// INITIALIZATION
// ============================================

console.log('[SyncWave] Starting server...');

// Serve static React frontend
app.use(express.static(path.join(__dirname, 'frontend', 'build')));
app.use(express.json());

// ============================================
// HTTP ROUTES
// ============================================

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: Date.now() });
});

// Get device info
app.get('/api/device', (req, res) => {
  const hostname = os.hostname();
  const interfaces = os.networkInterfaces();
  let ipAddress = 'localhost';

  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        ipAddress = iface.address;
        break;
      }
    }
  }

  res.json({
    id: getOrCreateDeviceId(),
    name: hostname,
    ip: ipAddress,
    port: PORT,
    capabilities: ['send', 'receive'],
  });
});

// Get list of connected devices
app.get('/api/devices', (req, res) => {
  const deviceList = Array.from(devices.values()).map(d => ({
    id: d.id,
    name: d.name,
    role: d.role,
    isActive: d.isActive,
    packetsReceived: d.packetsReceived || 0,
    lastSeen: d.lastSeen,
  }));

  res.json({ devices: deviceList, currentSender });
});

// Serve React app for all other routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'frontend', 'build', 'index.html'));
});

// ============================================
// WEBSOCKET CONNECTIONS
// ============================================

wss.on('connection', (ws, req) => {
  const clientId = uuidv4();
  const clientIp = req.socket.remoteAddress;
  let registeredName = `Device-${clientId.substring(0, 8)}`;

  console.log(`[WS] Client connected: ${clientId} from ${clientIp}`);

  // Register device
  const device = {
    id: clientId,
    clientIp,
    ws,
    name: registeredName,
    role: 'receiver',
    isActive: false,
    packetsReceived: 0,
    lastSeen: Date.now(),
  };

  devices.set(clientId, device);
  console.log(`[WS] Total connected devices: ${devices.size}`);

  // Send device list to all clients
  broadcastDeviceList();

  // ---- Message Handlers ----

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);

      switch (data.type) {
        case 'register':
          device.name = data.name || device.name;
          device.role = data.role || 'receiver';
          device.lastSeen = Date.now();
          broadcastDeviceList();
          console.log(`[WS] Device registered: ${device.name} (${device.role}) - ID: ${clientId}`);
          console.log(`[WS] Current devices in registry: ${Array.from(devices.values()).map(d => d.name).join(', ')}`);
          break;

        case 'set-role':
          const oldRole = device.role;
          device.role = data.role;
          console.log(`[WS] Role change: ${device.name} (${oldRole} → ${device.role})`);
          if (data.role === 'sender') {
            startSender(clientId);
          } else {
            stopSender(clientId);
          }
          broadcastDeviceList();
          break;

        case 'audio-data':
          handleAudioData(data, clientId);
          break;

        case 'request-stream':
          handleStreamRequest(data, clientId);
          break;

        case 'set-name':
          device.name = data.name || device.name;
          console.log(`[WS] Device name updated: ${device.name}`);
          broadcastDeviceList();
          break;

        default:
          console.log(`[WS] Unknown message type: ${data.type}`);
      }
    } catch (error) {
      console.error(`[WS] Message error:`, error.message);
    }
  });

  ws.on('close', () => {
    console.log(`[WS] Client disconnected: ${clientId} (${device.name})`);
    devices.delete(clientId);
    console.log(`[WS] Remaining devices: ${devices.size}`);
    if (currentSender === clientId) {
      stopSender(clientId);
    }
    broadcastDeviceList();
  });

  ws.on('error', (error) => {
    console.error(`[WS] WebSocket Error for ${clientId}:`, error.message);
  });
});

// ============================================
// BROADCAST FUNCTIONS
// ============================================

function broadcastDeviceList() {
  const deviceList = Array.from(devices.values()).map(d => ({
    id: d.id,
    name: d.name,
    role: d.role,
    isActive: d.isActive,
    clientIp: d.clientIp,
  }));

  const message = JSON.stringify({
    type: 'device-list',
    devices: deviceList,
    currentSender,
    timestamp: Date.now(),
  });

  console.log(`[Broadcast] Sending device list (${devices.size} devices) to all clients`);

  let sentCount = 0;
  devices.forEach(device => {
    if (device.ws.readyState === WebSocket.OPEN) {
      try {
        device.ws.send(message);
        sentCount++;
      } catch (error) {
        console.error(`[Broadcast] Failed to send to ${device.name}:`, error.message);
      }
    }
  });

  console.log(`[Broadcast] Sent to ${sentCount}/${devices.size} devices`);
}

function broadcastAudioFrame(frameData) {
  // frameData can be either the raw audio array or the full frame object with timestamp
  const audioArray = Array.isArray(frameData) ? frameData : frameData.audioData;
  const senderTimestamp = frameData.timestamp || Date.now();

  const message = JSON.stringify({
    type: 'audio-frame',
    data: audioArray,
    timestamp: senderTimestamp, // Sender's original timestamp for sync
    sequence: sequenceNumber,
    rtpTimestamp: rtpTimestamp, // RTP timestamp
  });

  devices.forEach((device, deviceId) => {
    if (deviceId !== currentSender && device.ws.readyState === WebSocket.OPEN) {
      device.ws.send(message);
    }
  });

  sequenceNumber = (sequenceNumber + 1) & 0xffff;
  rtpTimestamp += 480; // 480 samples per frame at 48kHz
}

// ============================================
// SENDER/RECEIVER CONTROL
// ============================================

function startSender(deviceId) {
  const device = devices.get(deviceId);
  if (device) {
    currentSender = deviceId;
    device.isActive = true;
    console.log(`[Server] Sender started: ${device.name}`);

    // Notify sender to start capturing
    if (device.ws.readyState === WebSocket.OPEN) {
      device.ws.send(JSON.stringify({
        type: 'start-capture',
        message: 'Start capturing system audio',
      }));
    }
  }
}

function stopSender(deviceId) {
  if (currentSender === deviceId) {
    const device = devices.get(deviceId);
    if (device) {
      device.isActive = false;
      console.log(`[Server] Sender stopped: ${device.name}`);

      // Notify sender to stop capturing
      if (device.ws.readyState === WebSocket.OPEN) {
        device.ws.send(JSON.stringify({
          type: 'stop-capture',
          message: 'Stop capturing system audio',
        }));
      }
    }
    currentSender = null;
    broadcastDeviceList();
  }
}

// ============================================
// AUDIO DATA HANDLING
// ============================================

function handleAudioData(data, senderId) {
  if (senderId !== currentSender) return; // Only accept from current sender

  // Relay audio to all receivers, including timestamp for synchronization
  broadcastAudioFrame(data);
}

function handleStreamRequest(data, clientId) {
  const device = devices.get(clientId);
  if (device && device.ws.readyState === WebSocket.OPEN) {
    device.ws.send(JSON.stringify({
      type: 'stream-ready',
      senderId: currentSender,
      message: 'Ready to receive audio',
    }));
  }
}

// ============================================
// UTILITIES
// ============================================

function getOrCreateDeviceId() {
  let id = global.DEVICE_ID;
  if (!id) {
    id = uuidv4();
    global.DEVICE_ID = id;
  }
  return id;
}

// ============================================
// SERVER START
// ============================================

server.listen(PORT, '0.0.0.0', () => {
  const ipAddress = getLocalIpAddress();
  console.log(`
╔════════════════════════════════════════╗
║          SyncWave Server               ║
╠════════════════════════════════════════╣
║ Server running on:                     ║
║   • http://localhost:${PORT}                  ║
║   • http://${ipAddress}:${PORT}              ║
║                                        ║
║ Open in any browser on your WiFi      ║
║ and broadcast/receive audio!          ║
╚════════════════════════════════════════╝
  `);
});

function getLocalIpAddress() {
  const interfaces = os.networkInterfaces();
  console.log('[Server] Available network interfaces:', Object.keys(interfaces));

  // Try common WiFi interface names first
  const wifiInterfaces = ['en0', 'wlan0', 'eth0', 'en1', 'wlan1'];
  for (const ifName of wifiInterfaces) {
    if (interfaces[ifName]) {
      for (const iface of interfaces[ifName]) {
        if (iface.family === 'IPv4' && !iface.internal) {
          console.log(`[Server] Found IP on ${ifName}: ${iface.address}`);
          return iface.address;
        }
      }
    }
  }

  // Fallback: try all interfaces
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        console.log(`[Server] Found IP on ${name}: ${iface.address}`);
        return iface.address;
      }
    }
  }

  console.log('[Server] Could not find IPv4 address, using localhost');
  return 'localhost';
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n[Server] Shutting down...');
  server.close(() => {
    console.log('[Server] Stopped');
    process.exit(0);
  });
});
