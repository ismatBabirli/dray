import { invoke } from "@/lib/transport";

/// Reports a feature the frontend owns, for the handful whose only chokepoint
/// is a click handler — the backend reports its own.
///
/// Consent, the install id and the opt-out all live in Rust and are read there
/// on every send, so this carries no state and answers no question: a call from
/// here is a request to report, not a decision that it will be.
///
/// **Never throws and never reports.** A failed `invoke` is swallowed whole,
/// since the one thing worse than a missing event is a feature failing because
/// counting it did.
export function trackFeature(feature: string) {
  void invoke("track_feature", { feature }).catch(() => {});
}

/// Reports a render error by **where** it broke, never by what it said.
///
/// Two closed things leave: React's error code, read off the minified message
/// (`#185` is an update loop), and the component stack's frames reduced to
/// `name@bundle:line:col` — our own minified bundle, which a source map of that
/// release names. A frame pointing anywhere else is dropped, so no path, prompt
/// or message text can ride along. Swallows failures like [`trackFeature`].
export function trackRenderError(error: unknown, componentStack: string) {
  // A component may throw anything, `null` included, and this runs inside the
  // boundary's catch: a throw here would take the Reload screen down too.
  const message = String((error as { message?: unknown } | null)?.message ?? "");
  const code = /Minified React error #(\d+)/.exec(message)?.[1];
  const frames = componentStack
    .split("\n")
    .map((line) => /^\s*at (\S+) \(tauri:\/\/localhost\/assets\/([\w.-]+\.js):(\d+):(\d+)\)$/.exec(line))
    .filter((m) => m !== null)
    .slice(0, 8)
    .map(([, name, file, line, col]) => `${name}@${file}:${line}:${col}`);
  void invoke("track_render_error", { code: code ? Number(code) : null, frames }).catch(() => {});
}

/// A frame of our own bundle in WebKit's `name@url:line:col` or Chromium's
/// `at name (url:line:col)`, reduced to `name@file:line:col`. Mac and Linux
/// serve the bundle from `tauri://localhost`, Windows from `http://tauri.localhost`;
/// any other frame is dropped.
const OWN_FRAME = /(?:tauri:\/\/localhost|https?:\/\/tauri\.localhost)\/assets\/([\w.-]+\.js):(\d+):(\d+)/;

export function bundleFrames(stack: string): string[] {
  return stack
    .split("\n")
    .flatMap((line) => {
      const at = OWN_FRAME.exec(line);
      if (!at) return [];
      const named = /^\s*at (\S+) \(/.exec(line)?.[1] ?? /^([^@]*)@/.exec(line)?.[1] ?? "";
      const name = named.replace(/[^\w$.]/g, "_") || "anonymous";
      return [`${name}@${at[1]}:${at[2]}:${at[3]}`];
    })
    .slice(0, 8);
}

/// What has been reported this run, so an error thrown on every frame is one
/// report rather than thousands.
const reportedErrors = new Set<string>();

/// Reports an uncaught error or rejected promise: its constructor name and its
/// frames of our own bundle, never its message. One with no frame of ours is
/// not ours to fix (a browser quirk, a `ResizeObserver` notice) and is dropped.
/// Swallows failures like [`trackFeature`].
export function trackJsError(error: unknown, rejection: boolean) {
  const frames = error instanceof Error ? bundleFrames(error.stack ?? "") : [];
  if (frames.length === 0) return;
  const name = error instanceof Error ? error.name : "Error";
  const key = `${name} ${frames[0]}`;
  if (reportedErrors.has(key) || reportedErrors.size >= 20) return;
  reportedErrors.add(key);
  void invoke("track_js_error", { name, rejection, frames }).catch(() => {});
}

/// Reports that the app is being used today.
///
/// Fired on every focus gain and throttled in Rust to one report per local day,
/// against the same key the backend's own two call sites claim — so this
/// decides nothing about whether anything is sent, and there is no state here
/// to keep in step with theirs.
///
/// Swallows failures for the same reason [`trackFeature`] does.
export function trackActiveDay() {
  void invoke("track_active_day").catch(() => {});
}
