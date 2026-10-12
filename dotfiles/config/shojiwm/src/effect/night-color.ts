import { loadShader, shaderStage, signal } from "shoji_wm";

const SHADER = loadShader("./src/effect/night-color.frag");
const greenGain = signal(1);
const blueGain = signal(1);
let active = false;
let temperature = 4000;

export function nightColorState() { return { enabled: active, temperature }; }
export function setNightColor(enabled: boolean, kelvin: number): void {
  active = enabled;
  temperature = kelvin;
  // Black-body approximation, normalized so 6500 K is exactly neutral.
  const t = kelvin / 100;
  const green = (99.4708025861 * Math.log(t) - 161.1195681661) / 255;
  const blue = (138.5177312231 * Math.log(t - 10) - 305.0447927307) / 255;
  const neutralGreen = (99.4708025861 * Math.log(65) - 161.1195681661) / 255;
  const neutralBlue = (138.5177312231 * Math.log(55) - 305.0447927307) / 255;
  greenGain.value = enabled ? Math.min(1, green / neutralGreen) : 1;
  blueGain.value = enabled ? Math.min(1, blue / neutralBlue) : 1;
}
export function nightColorStage() { return shaderStage(SHADER, { uniforms: { night_gains: [1, greenGain, blueGain] } }); }
