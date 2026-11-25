/// Onboarding's sounds: a shimmer under the logo's light, made in code.
/// Upstream follows it with a recorded song (#1567), which Wain drops. The shimmer was picked by
/// ear (#1421) from takes that live in this file's history, as does the synth
/// groove the song replaced.
///
/// Every voice stays above ~140Hz or leans on harmonics, since a laptop's
/// speakers drop anything lower.

import { useSyncExternalStore } from "react";

import { channel } from "@/lib/channel";

/// High soft sines drifting in like light on glass, landing as the logo's
/// light passes, `momentMs` from now.
export function playWelcomeSound(momentMs: number) {
  try {
    const ctx = new AudioContext();
    const master = ctx.createDynamicsCompressor();
    master.threshold.value = -20;
    master.ratio.value = 2.5;
    const out = ctx.createGain();
    out.gain.value = 1;
    master.connect(out).connect(ctx.destination);
    const hall = makeHall(ctx, 4);
    const wet = ctx.createGain();
    wet.gain.value = 0.45;
    hall.connect(wet).connect(master);
    const at = ctx.currentTime + Math.max(0.05, momentMs / 1000);
    [880, 1174.66, 1318.51, 1760].forEach((hz, i) => {
      const t = at - 0.2 + i * 0.12;
      const env = ctx.createGain();
      env.gain.setValueAtTime(0.0001, t);
      env.gain.exponentialRampToValueAtTime(0.05, t + 0.5);
      env.gain.exponentialRampToValueAtTime(0.0001, t + 3);
      env.connect(hall);
      voice(ctx, env, hz, "sine", 0, t, t + 3.1, 1);
    });
    setTimeout(() => void ctx.close(), (at - ctx.currentTime + 9) * 1000);
  } catch {
    // No audio output.
  }
}

function voice(ctx: BaseAudioContext, to: AudioNode, hz: number, type: OscillatorType, cents: number, from: number, until: number, level: number) {
  const osc = ctx.createOscillator();
  osc.type = type;
  osc.frequency.value = hz;
  osc.detune.value = cents;
  const g = ctx.createGain();
  g.gain.value = level;
  osc.connect(g).connect(to);
  osc.start(Math.max(ctx.currentTime, from));
  osc.stop(until);
}

/// `played` holds once the song has started in this run, so its control
/// outlives the song and offers it again.
type MusicState = { played: boolean; playing: boolean; muted: boolean };
const changed = channel<void>();
let music: MusicState = { played: false, playing: false, muted: false };
/// After the song's own level, so muting leaves the rise running on schedule.
let mute: GainNode | undefined;

function setMusic(next: Partial<MusicState>) {
  music = { ...music, ...next };
  changed.emit();
}

/// Whether the song has played, is playing, and whether the reader muted it.
export function useOnboardingMusic(): MusicState {
  return useSyncExternalStore(changed.subscribe, () => music);
}

/// Mutes or unmutes the song for the rest of this run.
export function setOnboardingMusicMuted(muted: boolean) {
  // A short glide, since a jump to silence clicks.
  if (mute) mute.gain.setTargetAtTime(muted ? 0 : 1, mute.context.currentTime, 0.03);
  setMusic({ muted });
}

/// Plays the song again from its first note, at full volume and unmuted.
export function replayOnboardingMusic() {
  setMusic({ muted: false });
  startOnboardingMusic(0);
}

/// Wain plays no song: upstream's sings "Welcome to Dray" (FORK.md). Never
/// playing leaves `played` false, so the mute button never draws.
export function startOnboardingMusic(_fullAtMs: number) {}

/// Decaying noise as an impulse: a large soft room.
function makeHall(ctx: BaseAudioContext, seconds: number) {
  const hall = ctx.createConvolver();
  const impulse = ctx.createBuffer(2, ctx.sampleRate * seconds, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const data = impulse.getChannelData(ch);
    for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / data.length, 3);
  }
  hall.buffer = impulse;
  return hall;
}
