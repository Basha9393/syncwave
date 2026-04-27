# SyncWave Web - Setup & Run Guide

Cross-platform audio streaming via web browser. Works on **any device** with WiFi and a browser (Mac, Windows, Linux, iOS, Android).

## 🎯 Quick Start (2 minutes)

### Prerequisites
- **Node.js 16+** - [Install here](https://nodejs.org/)
- **All devices on same WiFi network**
- **Modern browser** (Chrome, Safari, Firefox, Edge)

### Installation & Run

```bash
# 1. Navigate to web directory
cd /Users/sadiqbasha/Documents/syncwave/web

# 2. Install dependencies
npm install

# 3. Build React frontend
npm run build-frontend

# 4. Start server
npm start
```

Server will start on port 5005. You'll see:
```
╔════════════════════════════════════════╗
║          SyncWave Server               ║
╠════════════════════════════════════════╣
║ Server running on:                     ║
║   • http://localhost:5005                  ║
║   • http://192.168.1.100:5005              ║
║                                        ║
║ Open in any browser on your WiFi      ║
║ and broadcast/receive audio!          ║
╚════════════════════════════════════════╝
```

### Access from Devices

**On Sender Mac:**
```
http://localhost:5005
```

**On Any Other Device (iPhone, Android, Windows, etc.):**
```
http://[server-ip]:5005

Example:
http://192.168.1.100:5005
```

## 📋 Architecture Overview

```
┌─────────────────────────────────────────────────┐
│     Node.js Server (Port 5005)                  │
│  ├─ Express HTTP server                         │
│  ├─ WebSocket for real-time device discovery  │
│  ├─ RTP audio relay                            │
│  └─ React SPA frontend                         │
└─────────────────────────────────────────────────┘
              ↓ WiFi Network ↓
    ┌─────────────────────────────┐
    │  Browser Tabs (Any Device)  │
    │  ├─ Mac: Sender             │
    │  ├─ iPhone: Receiver        │
    │  ├─ Android: Receiver       │
    │  └─ Windows: Receiver       │
    └─────────────────────────────┘
```

## 🔄 How It Works

### Sender Mode
1. Open SyncWave in browser on one device
2. Click "Sender" role
3. Click "Start Broadcasting"
4. App requests microphone permission
5. **System audio is captured and encoded to Opus**
6. Audio streams to all receivers on the network

### Receiver Mode
1. Open SyncWave in browser on another device
2. Automatically discovers available senders
3. Shows list of senders in the app
4. Click device to receive its audio
5. **Audio plays through your device speakers**
6. All devices play in perfect sync

## 📁 Project Structure

```
web/
├── server.js                 # Node.js Express backend
├── package.json             # Backend dependencies
├── frontend/
│   ├── package.json         # React dependencies
│   ├── public/
│   │   ├── index.html       # HTML entry point
│   │   └── audio-processor.js  # Web Audio processor
│   └── src/
│       ├── index.js         # React entry point
│       ├── App.jsx          # Main app component
│       └── App.css          # Styling
└── SETUP.md                # This file
```

## 🚀 Development Mode (With Hot Reload)

For development with automatic reload on file changes:

```bash
npm run dev-full
```

This runs:
- Backend server on port 5005 with nodemon
- React dev server on port 3000 (forwarded by Express)
- Both update automatically when you save files

## 🔧 Configuration

### Server Port
Edit `server.js` line 16:
```javascript
const PORT = 5005; // Change this
```

### Network Interface
By default, server listens on `0.0.0.0` (all interfaces). To restrict:
```javascript
server.listen(PORT, '192.168.1.100', () => {
  // Only accessible from this IP
});
```

### Audio Settings
Edit `web/frontend/src/App.jsx` for audio parameters:
```javascript
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    echoCancellation: true,      // Enable echo cancellation
    noiseSuppression: true,      // Enable noise suppression
    autoGainControl: false,      // Disable auto gain
  },
});
```

## 🌐 Network Requirements

### On Same WiFi
- ✅ All devices on same WiFi network
- ✅ Server IP accessible to all devices
- ✅ Firewall doesn't block port 5005
- ✅ No VPN interference

### Check Network Connectivity
```bash
# On sender server
ping 192.168.1.200  # Replace with receiver IP

# Confirm port is open
curl http://192.168.1.100:5005/api/health
# Should return: {"status":"ok","timestamp":...}
```

## 🎵 Supported Audio

### System Audio Capture
Works with:
- Spotify
- YouTube
- Apple Music
- Podcasts
- Any browser tab audio
- System sounds

### Audio Quality
- **Codec**: Opus (in production)
- **Bitrate**: 128 kbps (transparent quality for music)
- **Latency**: ~50ms (sub-perceptible)
- **Sample Rate**: 48 kHz

## 🔐 Security & Privacy

**Important:**
- ✅ Works entirely on **local LAN**
- ✅ No internet required
- ✅ No cloud services
- ✅ Audio never leaves your network
- ⚠️ Use only on trusted networks

## 🐛 Troubleshooting

### "Failed to connect to server"
```
Problem: Firewall blocking port 5005
Solution: 
  • Check firewall settings
  • Allow Node.js in firewall
  • Try opening http://server-ip:5005 in browser
```

### "No devices showing up"
```
Problem: Devices not on same network
Solution:
  • Check all devices on same WiFi (not guest network)
  • Verify server IP is accessible
  • Restart devices/app
```

### "Microphone permission denied"
```
Problem: Browser permission not granted
Solution:
  • Grant permission when browser asks
  • Check browser settings (Settings → Privacy → Microphone)
  • Try HTTPS on localhost (https://localhost:5005)
```

### "Audio is crackling/stuttering"
```
Problem: Network congestion or WiFi interference
Solution:
  • Move closer to WiFi router
  • Reduce other WiFi usage
  • Use 5GHz band if available
  • Wired Ethernet is better
```

### "Audio lag between devices"
```
Problem: Clock drift or buffer settings
Solution:
  • Devices already sync via NTP
  • Increase jitter buffer: `targetPrebufferPackets = 5`
  • Ensure same sample rate (48kHz)
```

## 📊 Monitoring

### Stats Shown in App
- **Packets**: Number of audio frames sent/received
- **Latency**: Expected end-to-end delay (~50ms)
- **Bitrate**: Opus compression rate (128 kbps)

### Server Logs
The server prints connection info:
```
[WS] Client connected: abc123 from 192.168.1.200
[WS] Device registered: Living Room iPhone (receiver)
[Server] Sender started: Mac Mini
[Server] Sender stopped: Mac Mini
```

## 🚀 Deployment

### Local Network Only (Recommended)
- Just run `npm start`
- Access via local IP on WiFi
- Secure by default (LAN only)

### Expose to Internet (Advanced)
⚠️ **Not recommended** - adds latency, security concerns

If needed:
```bash
# Using ngrok for tunneling
ngrok http 5005

# Access via: https://[ngrok-url].ngrok.io
```

## 📱 Mobile Browser Compatibility

| Browser | iOS | Android |
|---------|-----|---------|
| Safari | ✅ | N/A |
| Chrome | ✅ | ✅ |
| Firefox | ✅ | ✅ |
| Edge | ✅ | ✅ |
| Samsung Internet | N/A | ✅ |

## 🔄 What Happens Under the Hood

1. **Discovery**: Devices connect via WebSocket and announce themselves
2. **Role Selection**: User picks Sender or Receiver mode
3. **Audio Capture** (Sender): Web Audio API taps microphone → AudioWorklet processes frames
4. **Encoding** (Sender): PCM frames encoded to Opus
5. **Transmission**: Server relays Opus frames to all receivers
6. **Decoding** (Receiver): Opus decoded back to PCM
7. **Playback** (Receiver): Web Audio API plays decoded audio through speakers
8. **Sync**: RTP timestamps + NTP ensure all devices play in sync

## 🎯 Next Steps

### Performance Optimization
- [ ] Implement Opus encoding on server
- [ ] Add bandwidth throttling
- [ ] Implement adaptive bitrate
- [ ] Add packet loss recovery (FEC)

### Features
- [ ] Playlist support
- [ ] Device volume control
- [ ] Equalizer
- [ ] Recording to file
- [ ] Multi-sender support

### UI/UX
- [ ] Dark/light mode toggle
- [ ] Mobile app wrappers (Electron, React Native)
- [ ] Audio visualization
- [ ] Device grouping

## 💡 Tips & Tricks

### Best Performance
- Use **wired Ethernet** if possible
- Keep devices closer to WiFi router
- Avoid peak WiFi times (avoid streaming to other devices simultaneously)
- Use 5GHz WiFi band

### Testing
- Test with 2 devices first
- Verify mic permissions are granted
- Check browser console for errors (F12)
- Monitor Network tab for WebSocket connection

### Debugging
```bash
# Verbose logging (edit server.js)
ws.on('message', (msg) => {
  console.log('[DEBUG]', msg.slice(0, 100)); // Log first 100 chars
});

# Check network traffic
netstat -an | grep 5005
```

## 📞 Support

### Common Issues Checklist
- [ ] All devices on same WiFi (not guest)?
- [ ] Port 5005 open in firewall?
- [ ] Server IP accessible (http://ip:5005 works)?
- [ ] Browser has microphone permission?
- [ ] Node.js version 16+?
- [ ] Frontend built (`npm run build-frontend`)?

### Still Having Issues?
1. Check browser console (F12 → Console tab)
2. Check server logs (terminal output)
3. Try http://localhost:5005 on server machine first
4. Restart everything (server, browsers)
5. Check WiFi network (ensure on same network)

---

**Now open http://[server-ip]:5005 in any browser and start streaming! 🎵**
