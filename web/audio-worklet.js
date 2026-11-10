/* Audio output: a ring buffer fed with emulator samples from the main thread. */
class GBAudio extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.size = 32768;
    this.l = new Float32Array(this.size);
    this.r = new Float32Array(this.size);
    this.rd = 0; this.wr = 0; this.count = 0;
    this.target = (options.processorOptions && options.processorOptions.target) || 3360;
    this.primed = false;
    this.lastL = 0; this.lastR = 0;
    this.blocks = 0; this.fillSum = 0;
    this.port.onmessage = (e) => {
      const s = e.data.samples;
      for (let i = 0; i < s.length; i += 2) {
        if (this.count >= this.size) { this.rd = (this.rd + 1) % this.size; this.count--; }
        this.l[this.wr] = s[i]; this.r[this.wr] = s[i + 1];
        this.wr = (this.wr + 1) % this.size; this.count++;
      }
      // never let latency build up: if far ahead, skip to the target
      if (this.count > this.target * 4) {
        const drop = this.count - this.target;
        this.rd = (this.rd + drop) % this.size; this.count -= drop;
      }
    };
  }

  process(inputs, outputs) {
    const out = outputs[0];
    const L = out[0], R = out[1] || out[0];
    if (!this.primed && this.count >= this.target) this.primed = true;
    for (let i = 0; i < L.length; i++) {
      if (this.primed && this.count > 0) {
        this.lastL = this.l[this.rd]; this.lastR = this.r[this.rd];
        this.rd = (this.rd + 1) % this.size; this.count--;
      } else {
        // underrun: fade out instead of clicking, then wait for the buffer to refill
        this.lastL *= 0.995; this.lastR *= 0.995;
        this.primed = false;
      }
      L[i] = this.lastL; R[i] = this.lastR;
    }
    this.fillSum += this.count;
    if (++this.blocks >= 16) {
      this.port.postMessage({ fill: this.fillSum / this.blocks });
      this.blocks = 0; this.fillSum = 0;
    }
    return true;
  }
}
registerProcessor('gb-audio', GBAudio);
