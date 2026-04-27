import React, { useState, useEffect, useRef } from 'react';
import './App.css';

const App = () => {
  const [deviceId, setDeviceId] = useState(null);
  const [deviceName, setDeviceName] = useState(null);
  const [editingName, setEditingName] = useState(false);
  const [tempName, setTempName] = useState('');
  const [role, setRole] = useState('receiver'); // 'sender' or 'receiver'
  const [isActive, setIsActive] = useState(false);
  const [devices, setDevices] = useState([]);
  const [currentSender, setCurrentSender] = useState(null);
  const [packetStats, setPacketStats] = useState({ sent: 0, received: 0 });
  const [connectionStatus, setConnectionStatus] = useState('connecting');
  const [connectionId, setConnectionId] = useState(null);
  const [volume, setVolume] = useState(100);

  const wsRef = useRef(null);
  const audioContextRef = useRef(null);
  const mediaStreamRef = useRef(null);
  const processorRef = useRef(null);
  const gainNodeRef = useRef(null);

  // Jitter buffer and continuous playback
  const audioBufferRef = useRef([]);  // Queue of audio frames
  const isPlayingRef = useRef(false);
  const playbackTimeRef = useRef(0);

  // Sender-side delayed monitoring (sync sender with receivers)
  const senderMonitorBufferRef = useRef([]);  // Buffer for sender's own audio with delay
  const senderMonitorPlayingRef = useRef(false);
  const senderMonitorTimeRef = useRef(0);

  // Synchronization
  const syncOffsetRef = useRef(0);  // Offset between sender and receiver clocks
  const senderClockRef = useRef(0); // Last known sender clock
  const receiverClockRef = useRef(0); // When we received it
  const frameCountRef = useRef(0); // Total frames processed
  const estimatedLatencyRef = useRef(100); // Estimated latency in ms (network + buffer)

  // ============================================
  // INITIALIZATION
  // ============================================

  useEffect(() => {
    initializeConnection();
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  const initializeConnection = async () => {
    try {
      // Generate or retrieve client-side device ID (persists across sessions)
      let clientDeviceId = localStorage.getItem('syncwave_device_id');
      if (!clientDeviceId) {
        clientDeviceId = `device-${Math.random().toString(36).substring(2, 9)}`;
        localStorage.setItem('syncwave_device_id', clientDeviceId);
        console.log('[App] Generated new device ID:', clientDeviceId);
      } else {
        console.log('[App] Using stored device ID:', clientDeviceId);
      }

      // Get or create device name
      let storedName = localStorage.getItem('syncwave_device_name');
      if (!storedName) {
        // Use hostname if available, otherwise use device ID
        const response = await fetch('/api/device');
        const deviceInfo = await response.json();
        storedName = deviceInfo.name || clientDeviceId;
        localStorage.setItem('syncwave_device_name', storedName);
      }

      setDeviceId(clientDeviceId);
      setDeviceName(storedName);
      setTempName(storedName);

      // Connect WebSocket
      const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${wsProtocol}//${window.location.host}`;
      console.log('[App] Connecting to WebSocket:', wsUrl);
      const ws = new WebSocket(wsUrl);

      ws.onopen = () => {
        console.log('[App] WebSocket connected');
        setConnectionStatus('connected');
        setConnectionId(Math.random().toString(36).substring(7));

        // Register device with client-side ID and name
        const registerMessage = {
          type: 'register',
          deviceId: clientDeviceId,
          name: storedName,
          role: role,
        };
        console.log('[App] Sending register message:', registerMessage);
        ws.send(JSON.stringify(registerMessage));
      };

      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          handleServerMessage(message);
        } catch (error) {
          console.error('[App] Failed to parse message:', error);
        }
      };

      ws.onerror = (error) => {
        console.error('[App] WebSocket error:', error);
        setConnectionStatus('error');
      };

      ws.onclose = () => {
        console.log('[App] WebSocket closed, reconnecting in 3s...');
        setConnectionStatus('disconnected');
        setTimeout(initializeConnection, 3000);
      };

      wsRef.current = ws;
    } catch (error) {
      console.error('[App] Failed to initialize connection:', error);
      setConnectionStatus('error');
      setTimeout(initializeConnection, 3000);
    }
  };

  // Save device name to localStorage and notify server
  const saveDeviceName = (newName) => {
    if (newName && newName.trim()) {
      const trimmedName = newName.trim();
      localStorage.setItem('syncwave_device_name', trimmedName);
      setDeviceName(trimmedName);
      setEditingName(false);

      // Notify server of name change
      if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({
          type: 'set-name',
          name: trimmedName,
        }));
      }
    }
  };

  // ============================================
  // MESSAGE HANDLING
  // ============================================

  const handleServerMessage = (message) => {
    switch (message.type) {
      case 'device-list':
        console.log('[App] Received device list:', message.devices);
        setDevices(message.devices || []);
        setCurrentSender(message.currentSender);
        break;

      case 'start-capture':
        console.log('[App] Server requested to start capturing');
        if (role === 'sender') {
          startCapture();
        }
        break;

      case 'stop-capture':
        console.log('[App] Server requested to stop capturing');
        if (role === 'sender') {
          stopCapture();
        }
        break;

      case 'audio-frame':
        if (role === 'receiver') {
          playAudioFrame(message.data, message.timestamp);
          setPacketStats(prev => ({
            ...prev,
            received: prev.received + 1,
          }));
        }
        break;

      default:
        console.log('[App] Unknown message type:', message.type);
        break;
    }
  };

  // ============================================
  // ROLE SWITCHING
  // ============================================

  const switchRole = async (newRole) => {
    if (isActive) {
      stopAudio();
    }

    setRole(newRole);

    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: 'set-role',
        role: newRole,
      }));
    }
  };

  // ============================================
  // SENDER: AUDIO CAPTURE
  // ============================================

  const startCapture = async () => {
    try {
      console.log('[Audio] Starting audio capture...');

      // Request microphone access (for system audio capture)
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,   // Disable - can filter out audio
          noiseSuppression: false,   // Disable - can filter out audio
          autoGainControl: false,    // Disable - can reduce signal to silence
          sampleRate: 48000,
        },
      });

      mediaStreamRef.current = stream;
      console.log('[Audio] Microphone access granted, stream tracks:', stream.getTracks().length);

      // Initialize audio context
      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      audioContextRef.current = audioContext;

      console.log('[Audio] AudioContext created, sample rate:', audioContext.sampleRate);

      const source = audioContext.createMediaStreamSource(stream);
      console.log('[Audio] MediaStreamSource created');

      // Add audio processing chain to reduce noise while keeping audio
      // 1. High-pass filter to remove hum (below 80Hz)
      const highPass = audioContext.createBiquadFilter();
      highPass.type = 'highpass';
      highPass.frequency.value = 80; // Remove low-frequency hum
      console.log('[Audio] High-pass filter added (80Hz)');

      // 2. Gentle compression to prevent clipping
      const gainNode = audioContext.createGain();
      gainNode.gain.value = 0.8; // Slightly reduce to prevent distortion
      console.log('[Audio] Gain node added (0.8x)');

      // Create a script processor for real-time audio processing
      let processor;
      let isUsingWorklet = false;

      try {
        // Try AudioWorklet first (preferred)
        console.log('[Audio] Attempting to load AudioWorklet...');
        await audioContext.audioWorklet.addModule('audio-processor.js');
        processor = new AudioWorkletNode(audioContext, 'audio-processor');
        isUsingWorklet = true;
        console.log('[Audio] ✅ Using AudioWorklet processor');
      } catch (workletError) {
        console.warn('[Audio] AudioWorklet failed, using ScriptProcessor fallback:', workletError.message);

        // Fallback: Use ScriptProcessor (deprecated but widely supported)
        processor = audioContext.createScriptProcessor(4096, 1, 1);
        console.log('[Audio] ✅ Using ScriptProcessor fallback');

        let processCount = 0;
        processor.onaudioprocess = (event) => {
          processCount++;
          const inputData = event.inputBuffer.getChannelData(0);

          // Only log first few to avoid console spam
          if (processCount === 1) {
            console.log('[Audio] ScriptProcessor started, got', inputData.length, 'samples');
          }

          // Check if we have actual audio data
          let hasAudio = false;
          for (let i = 0; i < inputData.length; i++) {
            if (Math.abs(inputData[i]) > 0.01) {
              hasAudio = true;
              break;
            }
          }

          if (processCount === 1) {
            console.log('[Audio] Audio data present:', hasAudio);
          }

          // Convert Float32 to Int16
          const int16Data = new Int16Array(inputData.length);
          for (let i = 0; i < inputData.length; i++) {
            const sample = Math.max(-1, Math.min(1, inputData[i]));
            int16Data[i] = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
          }

          // Send to server with sync info
          if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
            wsRef.current.send(JSON.stringify({
              type: 'audio-data',
              audioData: Array.from(int16Data),
              timestamp: Date.now(),
              sequence: processCount,
            }));

            setPacketStats(prev => ({
              ...prev,
              sent: prev.sent + 1,
            }));

            if (processCount === 1) {
              console.log('[Audio] First packet sent to server');
            }
          } else if (processCount === 1) {
            console.error('[Audio] WebSocket not ready, state:', wsRef.current?.readyState);
          }
        };
      }

      if (isUsingWorklet && processor.port) {
        // AudioWorklet version
        console.log('[Audio] Setting up AudioWorklet message handler...');
        processor.port.onmessage = (event) => {
          const message = event.data;
          console.log('[Audio] AudioWorklet message received:', message.type, message.length, 'samples');

          // Extract the audio data array from the message
          const audioData = message.data;

          if (!Array.isArray(audioData)) {
            console.error('[Audio] Invalid data from AudioWorklet, expected array, got', typeof audioData);
            return;
          }

          const captureTimestamp = Date.now();

          // Send to server with sync info
          if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
            wsRef.current.send(JSON.stringify({
              type: 'audio-data',
              audioData: audioData,
              timestamp: captureTimestamp,
              sequence: message.data.length || 0,
            }));

            setPacketStats(prev => ({
              ...prev,
              sent: prev.sent + 1,
            }));
          } else {
            console.warn('[Audio] WebSocket not ready for AudioWorklet data');
          }

          // NOTE: Sender monitoring disabled to prevent feedback
          // Sender already hears original audio in real-time from system
          // Delayed playback creates feedback loop when microphone captures original + delayed
          // Receivers are already perfectly synced via network clock
        };

        processor.port.onerror = (error) => {
          console.error('[Audio] AudioWorklet error:', error);
        };
      }

      // Connect audio chain: source → highPass → gainNode → processor → destination
      source.connect(highPass);
      highPass.connect(gainNode);
      gainNode.connect(processor);
      processor.connect(audioContext.destination);

      console.log('[Audio] Audio processing chain connected');

      processorRef.current = processor;
      setIsActive(true);
      setConnectionStatus('broadcasting');
      console.log('[Audio] ✅ Audio capture started successfully');
    } catch (error) {
      console.error('[Audio] ❌ Failed to start capture:', error);
      console.error('[Audio] Error details:', error.name, error.message);
      setConnectionStatus('error');
    }
  };

  const stopCapture = () => {
    try {
      console.log('[Audio] Stopping audio capture...');

      // Stop sender monitoring
      senderMonitorPlayingRef.current = false;
      senderMonitorBufferRef.current = [];

      if (mediaStreamRef.current) {
        mediaStreamRef.current.getTracks().forEach(track => {
          track.stop();
          console.log('[Audio] Stopped track:', track.kind);
        });
        mediaStreamRef.current = null;
      }

      if (processorRef.current) {
        processorRef.current.disconnect();
        processorRef.current = null;
        console.log('[Audio] Disconnected processor');
      }

      if (audioContextRef.current && role === 'sender') {
        audioContextRef.current.close();
        audioContextRef.current = null;
        console.log('[Audio] Closed audio context');
      }

      setIsActive(false);
      setConnectionStatus('connected');
      console.log('[Audio] Audio capture stopped');
    } catch (error) {
      console.error('[Audio] Error stopping capture:', error);
    }
  };

  // ============================================
  // RECEIVER: AUDIO PLAYBACK
  // ============================================

  // Sender monitoring: Play sender's own audio with receiver latency offset
  const playSenderMonitorFrame = (audioData, captureTimestamp) => {
    try {
      if (!audioContextRef.current) {
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        audioContextRef.current = audioContext;

        // Create gain node for volume control
        const gainNode = audioContext.createGain();
        gainNode.gain.value = volume / 100;
        gainNode.connect(audioContext.destination);
        gainNodeRef.current = gainNode;

        console.log('[Audio] AudioContext created for sender monitoring');
      }

      // Add frame to sender's monitoring buffer with delay compensation
      senderMonitorBufferRef.current.push({
        data: audioData,
        timestamp: captureTimestamp,
      });

      // Start sender monitoring playback if not already running
      if (!senderMonitorPlayingRef.current) {
        senderMonitorPlayingRef.current = true;
        senderMonitorPlayback();
      }
    } catch (error) {
      console.error('[Audio] Sender monitoring error:', error);
    }
  };

  // Delayed playback for sender (matches receiver delay)
  const senderMonitorPlayback = async () => {
    const audioContext = audioContextRef.current;
    if (!audioContext) return;

    try {
      while (senderMonitorPlayingRef.current) {
        const bufferSize = senderMonitorBufferRef.current.length;

        // Wait for buffer to accumulate frames (accounting for network latency)
        const minFramesNeeded = Math.ceil(estimatedLatencyRef.current / 10); // 10ms per frame
        if (bufferSize < minFramesNeeded) {
          await new Promise(resolve => setTimeout(resolve, 5));
          continue;
        }

        // Get next frame
        const frameObj = senderMonitorBufferRef.current.shift();
        if (!frameObj) continue;

        const audioData = frameObj.data;
        const frameDuration = audioData.length / 48000;

        // Convert 16-bit to Float32
        const float32Data = new Float32Array(audioData.length);
        for (let i = 0; i < audioData.length; i++) {
          float32Data[i] = audioData[i] / 32768.0;
        }

        // Create audio buffer
        const audioBuffer = audioContext.createBuffer(1, float32Data.length, 48000);
        audioBuffer.getChannelData(0).set(float32Data);

        // Create and play source
        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;

        if (gainNodeRef.current) {
          source.connect(gainNodeRef.current);
        } else {
          source.connect(audioContext.destination);
        }

        // Schedule playback
        source.start(senderMonitorTimeRef.current);
        senderMonitorTimeRef.current += frameDuration;
      }

      senderMonitorPlayingRef.current = false;
    } catch (error) {
      console.error('[Audio] Sender monitor playback error:', error);
      senderMonitorPlayingRef.current = false;
    }
  };

  const playAudioFrame = (audioData, senderTimestamp) => {
    try {
      if (!audioContextRef.current) {
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        audioContextRef.current = audioContext;

        // Create gain node for volume control
        const gainNode = audioContext.createGain();
        gainNode.gain.value = volume / 100;
        gainNode.connect(audioContext.destination);
        gainNodeRef.current = gainNode;

        console.log('[Audio] AudioContext created for sync playback');
      }

      // Validate audio data
      if (!Array.isArray(audioData) || audioData.length === 0) {
        console.warn('[Audio] Invalid or empty audio data');
        return;
      }

      // Update sender clock info for synchronization
      if (senderTimestamp) {
        const now = Date.now();
        const networkLatency = Math.max(0, now - senderTimestamp);

        // Estimate sync offset (only on first frame and periodically)
        frameCountRef.current++;
        if (frameCountRef.current === 1 || frameCountRef.current % 100 === 0) {
          senderClockRef.current = senderTimestamp;
          receiverClockRef.current = now;
          syncOffsetRef.current = networkLatency;

          // Update sender's estimated latency (network + buffer delay)
          const estimatedTotalLatency = networkLatency + 50; // Add 50ms for jitter buffer
          estimatedLatencyRef.current = estimatedTotalLatency;

          if (frameCountRef.current === 1) {
            console.log('[Audio] Sync initialized - latency:', networkLatency, 'ms, estimated total:', estimatedTotalLatency, 'ms');
          }
        }
      }

      // Add frame to jitter buffer with timing info
      audioBufferRef.current.push({
        data: audioData,
        timestamp: senderTimestamp,
        arrivalTime: Date.now(),
      });

      // Start playback loop if not already running
      if (!isPlayingRef.current) {
        isPlayingRef.current = true;
        // Initialize playback time reference on first frame
        if (frameCountRef.current === 1) {
          playbackTimeRef.current = audioContextRef.current?.currentTime || 0;
          console.log('[Audio] Playback started, synced to sender clock');
        }
        continuousPlayback();
      }

      // Debug logging (less frequent to avoid spam)
      if (packetStats.received % 100 === 0) {
        console.log('[Audio] Buffer:', audioBufferRef.current.length, 'frames, Sync offset:', Math.round(syncOffsetRef.current), 'ms');
      }
    } catch (error) {
      console.error('[Audio] Playback error:', error);
    }
  };

  // Network-synced playback - all devices play at same wall-clock time
  const continuousPlayback = async () => {
    const audioContext = audioContextRef.current;
    if (!audioContext) return;

    try {
      while (isPlayingRef.current) {
        const bufferSize = audioBufferRef.current.length;

        // Maintain 5 frame buffer for jitter absorption (50ms - imperceptible)
        // Handles network delays without noticeable latency
        if (bufferSize < 5) {
          await new Promise(resolve => setTimeout(resolve, 5));
          continue;
        }

        // Get next frame
        const frameObj = audioBufferRef.current.shift();
        if (!frameObj) continue;

        const audioData = frameObj.data;
        const senderTimestamp = frameObj.timestamp;
        const frameDuration = audioData.length / 48000;

        // Convert 16-bit to Float32
        const float32Data = new Float32Array(audioData.length);
        for (let i = 0; i < audioData.length; i++) {
          float32Data[i] = audioData[i] / 32768.0;
        }

        // Create audio buffer
        const audioBuffer = audioContext.createBuffer(
          1, // mono
          float32Data.length,
          48000 // 48kHz
        );

        audioBuffer.getChannelData(0).set(float32Data);

        // Create and play source
        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;

        if (gainNodeRef.current) {
          source.connect(gainNodeRef.current);
        } else {
          source.connect(audioContext.destination);
        }

        // CRITICAL: Schedule based on SENDER TIME for cross-device sync
        // Calculate time elapsed since sender created this frame
        const now = Date.now();
        const elapsedSinceSend = (now - senderTimestamp) / 1000; // Convert to seconds

        // Schedule to play after the elapsed time + small buffer
        // This ensures all receivers (regardless of join time) schedule at similar offsets
        const playTime = Math.max(
          audioContext.currentTime + 0.02, // Minimum 20ms in future
          audioContext.currentTime + elapsedSinceSend
        );

        source.start(playTime);
        playbackTimeRef.current = playTime + frameDuration;

        if (frameCountRef.current % 50 === 0) {
          console.log('[Audio] Playing frame at +' + (elapsedSinceSend * 1000).toFixed(0) + 'ms from send');
        }
      }

      isPlayingRef.current = false;
    } catch (error) {
      console.error('[Audio] Playback error:', error);
      isPlayingRef.current = false;
    }
  };

  // ============================================
  // CONTROLS
  // ============================================

  const startAudio = async () => {
    if (role === 'sender') {
      startCapture();
    } else {
      // For receiver, just signal ready
      if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({
          type: 'request-stream',
          message: 'Ready to receive',
        }));
      }
      setIsActive(true);
      setConnectionStatus('receiving');
    }
  };

  const stopAudio = () => {
    if (role === 'sender') {
      stopCapture();
    } else {
      setIsActive(false);
      setConnectionStatus('connected');
    }
  };

  // ============================================
  // RENDER
  // ============================================

  return (
    <div className="app">
      <div className="header">
        <div className="logo">
          <span className="icon">🎵</span>
          <h1>SyncWave</h1>
        </div>
        <div className="device-info">
          <div className="device-name-container">
            {editingName ? (
              <div className="device-name-editor">
                <input
                  type="text"
                  value={tempName}
                  onChange={(e) => setTempName(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') saveDeviceName(tempName);
                    if (e.key === 'Escape') {
                      setEditingName(false);
                      setTempName(deviceName);
                    }
                  }}
                  autoFocus
                  maxLength={30}
                />
                <button onClick={() => saveDeviceName(tempName)} className="btn-save">✓</button>
              </div>
            ) : (
              <span
                className="device-name"
                onClick={() => {
                  setEditingName(true);
                  setTempName(deviceName);
                }}
                title="Click to edit device name"
              >
                {deviceName} <span className="edit-hint">✎</span>
              </span>
            )}
          </div>
        </div>
        <div className="status">
          <div className={`status-indicator ${connectionStatus}`}></div>
          <span className="status-text">
            {connectionStatus === 'connecting' && 'Connecting...'}
            {connectionStatus === 'connected' && 'Ready'}
            {connectionStatus === 'broadcasting' && 'Broadcasting'}
            {connectionStatus === 'receiving' && 'Receiving'}
            {connectionStatus === 'error' && 'Error'}
            {connectionStatus === 'disconnected' && 'Disconnected'}
          </span>
        </div>
      </div>

      <div className="container">
        {/* Role Selector */}
        <div className="role-selector">
          <button
            className={`role-btn ${role === 'sender' ? 'active' : ''}`}
            onClick={() => switchRole('sender')}
            disabled={connectionStatus !== 'connected' && connectionStatus !== 'broadcasting'}
          >
            <span className="icon">📡</span>
            <span className="label">Sender</span>
            <span className="desc">Broadcast audio</span>
          </button>

          <button
            className={`role-btn ${role === 'receiver' ? 'active' : ''}`}
            onClick={() => switchRole('receiver')}
            disabled={connectionStatus !== 'connected' && connectionStatus !== 'receiving'}
          >
            <span className="icon">🔊</span>
            <span className="label">Receiver</span>
            <span className="desc">Listen to sender</span>
          </button>
        </div>

        {/* Content Area */}
        <div className="content">
          {role === 'sender' ? (
            <SenderView
              isActive={isActive}
              onStart={startAudio}
              onStop={stopAudio}
              devices={devices}
              packetStats={packetStats}
            />
          ) : (
            <ReceiverView
              isActive={isActive}
              onStart={startAudio}
              onStop={stopAudio}
              currentSender={currentSender}
              allDevices={devices}
              packetStats={packetStats}
              volume={volume}
              onVolumeChange={(newVolume) => {
                setVolume(newVolume);
                if (gainNodeRef.current) {
                  gainNodeRef.current.gain.value = newVolume / 100;
                }
              }}
            />
          )}
        </div>

        {/* Device List */}
        <div className="device-list">
          <h3>Connected Devices</h3>
          {devices.length === 0 ? (
            <p className="empty">No devices connected</p>
          ) : (
            <ul>
              {devices.map(device => (
                <li key={device.id} className={device.isActive ? 'active' : ''}>
                  <span className="device-icon">
                    {device.role === 'sender' ? '📡' : '🔊'}
                  </span>
                  <span className="device-name">{device.name}</span>
                  <span className={`badge ${device.role}`}>{device.role}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Stats */}
      <div className="stats">
        <div className="stat">
          <span className="label">Packets</span>
          <span className="value">
            {role === 'sender' ? packetStats.sent : packetStats.received}
          </span>
        </div>
        <div className="stat">
          <span className="label">Latency</span>
          <span className="value">~50ms</span>
        </div>
        <div className="stat">
          <span className="label">Bitrate</span>
          <span className="value">128 kbps</span>
        </div>
      </div>
    </div>
  );
};

// ============================================
// SENDER VIEW
// ============================================

const SenderView = ({ isActive, onStart, onStop, devices, packetStats }) => {
  return (
    <div className="view sender-view">
      <div className="action-card">
        {isActive ? (
          <div className="status-active">
            <div className="pulse-ring"></div>
            <h2>Broadcasting</h2>
            <p>Your system audio is being streamed</p>
            <button className="btn btn-danger" onClick={onStop}>
              Stop Broadcasting
            </button>
          </div>
        ) : (
          <div className="status-inactive">
            <h2>Start Broadcasting</h2>
            <p>Stream your system audio to all connected devices</p>
            <button className="btn btn-primary" onClick={onStart}>
              Start Broadcasting
            </button>
          </div>
        )}
      </div>

      {isActive && (
        <div className="info-card">
          <h3>Connected Receivers</h3>
          {devices.filter(d => d.role === 'receiver').length === 0 ? (
            <p className="empty">Waiting for receivers to connect...</p>
          ) : (
            <ul className="receiver-list">
              {devices
                .filter(d => d.role === 'receiver')
                .map(device => (
                  <li key={device.id}>
                    <span className="device-name">{device.name}</span>
                    <span className="status">Receiving</span>
                  </li>
                ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
};

// ============================================
// RECEIVER VIEW
// ============================================

const ReceiverView = ({ isActive, onStart, onStop, currentSender, allDevices, packetStats, volume, onVolumeChange }) => {
  const senderDevice = allDevices.find(d => d.id === currentSender);

  return (
    <div className="view receiver-view">
      <div className="action-card">
        {isActive ? (
          <div className="status-active">
            <div className="pulse-ring"></div>
            <h2>Connected</h2>
            <p>Receiving from {senderDevice?.name || 'sender'}</p>
            <p className="packets-info">Received: {packetStats.received} packets</p>
            <button className="btn btn-danger" onClick={onStop}>
              Disconnect
            </button>
          </div>
        ) : (
          <div className="status-inactive">
            <h2>Listen to Audio</h2>
            <p>Select a sender and start receiving</p>
            <button
              className="btn btn-primary"
              onClick={onStart}
              disabled={!currentSender}
            >
              {currentSender ? 'Start Listening' : 'No Senders Available'}
            </button>
          </div>
        )}
      </div>

      <div className="info-card">
        <h3>Available Senders</h3>
        {allDevices.filter(d => d.role === 'sender').length === 0 ? (
          <p className="empty">Looking for senders...</p>
        ) : (
          <ul className="sender-list">
            {allDevices
              .filter(d => d.role === 'sender')
              .map(device => (
                <li key={device.id} className={device.id === currentSender ? 'selected' : ''}>
                  <span className="device-name">{device.name}</span>
                  <span className={`status ${device.isActive ? 'active' : 'idle'}`}>
                    {device.isActive ? 'Broadcasting' : 'Idle'}
                  </span>
                </li>
              ))}
          </ul>
        )}
      </div>

      {isActive && (
        <div className="info-card">
          <h3>Now Playing</h3>
          <div className="player">
            <div className="waveform">
              {[...Array(30)].map((_, i) => (
                <div
                  key={i}
                  className="bar"
                  style={{
                    height: `${20 + Math.random() * 60}%`,
                    animation: `pulse ${0.3 + Math.random() * 0.2}s ease-in-out infinite`,
                  }}
                ></div>
              ))}
            </div>
            <div className="player-controls">
              <button disabled title="Skip to previous">⏮</button>
              <button disabled title="Pause/Resume (live stream)">⏸</button>
              <button disabled title="Skip to next">⏭</button>
            </div>
            <div className="volume">
              <span>Volume: {volume}%</span>
              <input
                type="range"
                min="0"
                max="100"
                value={volume}
                onChange={(e) => onVolumeChange(parseInt(e.target.value))}
                title="Adjust volume"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default App;
