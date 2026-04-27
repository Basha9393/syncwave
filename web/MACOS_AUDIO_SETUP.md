# macOS System Audio Setup for SyncWave

## The Challenge

By default, web browsers can only access the **microphone input**, not system audio output. To stream system audio (Spotify, YouTube, etc.) with SyncWave, you need to set up **audio routing**.

## Solution: Multi-Output Device (Best Option)

### Option 1: Using Built-in Multi-Output Device (Recommended)

macOS has a built-in feature to create aggregate audio devices. Here's how:

#### Step 1: Create an Aggregate Device
1. Open **Audio MIDI Setup** (Applications → Utilities)
2. Click the **"+" button** at the bottom left
3. Select **"Create Multi-Output Device"**
4. Name it something like "SyncWave Audio"
5. Check both:
   - ✅ **Built-in Output** (for hearing the audio)
   - ✅ **Built-in Microphone** (or your microphone)

#### Step 2: Configure as System Output
1. Go to **System Settings → Sound**
2. Set **Output** to your new Multi-Output Device
3. Set **Input** to your new Multi-Output Device

#### Step 3: Test with SyncWave
1. Start SyncWave: `npm start`
2. Open sender: `http://localhost:5005`
3. Click "Sender" → "Start Broadcasting"
4. Play music/audio on your Mac
5. Audio should stream to receivers! ✅

---

### Option 2: Using BlackHole (Virtual Audio Device)

If the built-in Multi-Output Device doesn't work, install **BlackHole**:

#### Installation
1. Download BlackHole: https://github.com/ExistentialAudio/BlackHole
2. Install the free version
3. Restart your Mac

#### Setup
1. Go to **System Settings → Sound → Output**
2. Select **"BlackHole 2ch"** as output device
3. Go to **Input**
4. Select **"BlackHole 2ch"** as input device

#### Test with SyncWave
1. Start SyncWave: `npm start`
2. Open sender: `http://localhost:5005`
3. Click "Sender" → "Start Broadcasting"
4. Play music/audio
5. Audio streams to receivers! ✅

---

### Option 3: Using Loopback (Professional)

If you need advanced features:

1. Download **Loopback**: https://rogueamoeba.com/loopback/
2. Create a virtual input device
3. Route system audio to it
4. Select it as input in SyncWave

---

## How It Works

```
System Audio (Spotify, YouTube, etc.)
    ↓
Multi-Output Device / BlackHole (captures system audio)
    ↓
Browser getUserMedia() (accesses virtual input)
    ↓
SyncWave AudioWorklet (processes audio)
    ↓
WebSocket → Server → All Receivers
    ↓
🔊 Remote audio playback
```

---

## Troubleshooting

### "Audio still doesn't stream"
1. Check that **Input device** is set to Multi-Output/BlackHole
2. Check that **Output device** is also set to Multi-Output/BlackHole
3. Restart the browser
4. Restart SyncWave (`npm start`)

### "I hear no sound on my Mac"
1. Make sure Multi-Output Device has:
   - ✅ Built-in Output checked
   - ✅ Built-in Microphone checked
2. Adjust volume in Sound settings
3. Test with YouTube or Spotify

### "Only microphone audio streams, not system audio"
This means the input device is set to just the microphone, not the Multi-Output Device. Fix:
1. Open **System Settings → Sound → Input**
2. Select **Multi-Output Device** (or BlackHole)
3. Restart browser
4. Try again

### "Audio is quiet or distorted"
1. Adjust **System Volume** in Sound settings
2. Reduce **Gain** in SyncWave receiver (volume slider)
3. Make sure Multi-Output Device isn't set to very low level

---

## Windows & Linux Users

### Windows
Windows audio routing is different. You can use:
1. **VB-Audio Virtual Cable**: https://vb-audio.com/Cable/
2. **VoiceMeeter**: https://vb-audio.com/Voicemeeter/
3. Follow similar setup steps

### Linux
Linux audio routing depends on your system:
1. **PulseAudio**: Use `pavucontrol` to create loopback
2. **ALSA**: Use `arecord` with loopback plugin
3. **JACK**: Professional audio routing

---

## Why This Is Needed

Web browsers have **security restrictions** that prevent directly accessing system audio. They can only access:
- ✅ Microphone input (via `getUserMedia`)
- ✅ Loopback/Virtual devices (via `getUserMedia`)
- ✅ Screen sharing audio (in some browsers)

System audio routing solves this by:
1. Creating a virtual "microphone" that captures system output
2. Allowing the browser to access it via `getUserMedia`
3. Enabling full system audio streaming

---

## Future Solutions

In the future, we might be able to use:
- ✅ **Web Audio API System Audio Capture** (when browsers support it)
- ✅ **Display Capture with audio** (experimental feature)
- ✅ **Native app wrapper** (Electron) with system audio access

For now, **Multi-Output Device setup** is the most reliable method.

---

## Quick Reference

### macOS
```
Audio MIDI Setup → Create Multi-Output Device
→ System Settings → Sound
→ Set Input AND Output to Multi-Output Device
→ SyncWave ready!
```

### With BlackHole
```
Install BlackHole from GitHub
→ System Settings → Sound
→ Set Input AND Output to "BlackHole 2ch"
→ SyncWave ready!
```

---

## Test Your Setup

Before starting SyncWave:

1. **Open System Preferences → Sound**
2. **Play music** on your Mac
3. **Check Input levels** - should show activity from system audio
4. If you see input levels moving → Setup is correct! ✅
5. If no input activity → Audio routing not configured correctly

Once input levels show system audio, SyncWave will work perfectly!

---

## Questions?

If you're still having issues:
1. Make sure **Input device** is Multi-Output/BlackHole (not "Built-in Microphone")
2. Make sure **Output device** is set to Multi-Output/BlackHole
3. Restart browser and SyncWave server
4. Check that system audio is actually playing before starting broadcast

The key is making sure the browser's microphone input is set to the aggregate/virtual device, not the built-in microphone!
