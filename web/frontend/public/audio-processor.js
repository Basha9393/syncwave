/**
 * Audio Processor Worklet
 * Runs on the Web Audio processing thread
 * Processes audio frames and sends them to the main thread
 */

class AudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.frameBuffer = [];
    this.frameSize = 480; // 10ms @ 48kHz = 480 samples
    console.log('[AudioProcessor] Initialized with frameSize:', this.frameSize);
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];

    if (!input || input.length === 0) {
      return true;
    }

    // Mix all channels to mono (usually just 1 channel from microphone)
    const channelData = input[0];

    // Add samples to buffer
    for (let i = 0; i < channelData.length; i++) {
      this.frameBuffer.push(channelData[i]);
    }

    // When we have a full frame, send it
    while (this.frameBuffer.length >= this.frameSize) {
      const frame = this.frameBuffer.slice(0, this.frameSize);
      this.frameBuffer = this.frameBuffer.slice(this.frameSize);

      // Convert Float32 audio to Int16 for transmission
      const int16Array = new Int16Array(frame.length);
      for (let i = 0; i < frame.length; i++) {
        // Clamp to [-1, 1]
        const sample = Math.max(-1, Math.min(1, frame[i]));
        // Convert to 16-bit signed integer
        int16Array[i] = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
      }

      // Send to main thread
      this.port.postMessage({
        type: 'audio-frame',
        data: Array.from(int16Array),
        length: int16Array.length,
        sampleRate: 48000,
      });
    }

    // Note: We don't pass through to output here because:
    // 1. Output arrays in AudioWorklet are read-only
    // 2. The source is already connected to destination for monitoring
    // 3. We just need to send audio to the server

    return true;
  }
}

registerProcessor('audio-processor', AudioProcessor);
