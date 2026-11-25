import type { ReactNode } from "react";

import WindowControls from "@/components/layout/WindowControls";
import MuteButton from "@/components/onboarding/MuteButton";
import type { SignInMethod } from "@/types/events";

/// What the gate is showing. `revoked` is a saved sign-in the site turned
/// away; `waiting` a browser sign-in in flight, `finishing` once the browser
/// is back and it can no longer be cancelled. `emailOff` is the site saying
/// email sign-in isn't open yet, `lastUsed` the way in this app last took.
export type GateView =
  | {
      kind: "choose";
      revoked: boolean;
      error: string | null;
      offline: boolean;
      emailOff: boolean;
      lastUsed: SignInMethod | null;
    }
  | { kind: "waiting"; method: SignInMethod; finishing: boolean };

const METHOD: Record<SignInMethod, string> = { github: "GitHub", google: "Google", email: "email" };

/// The window a signed-out reader sees instead of the app (#1277): black, the
/// site's striped tiles along the bottom, and the three ways in as cards.
/// Always dark, whatever the theme, since it is the brand's own page.
export default function SignInGate({
  view,
  onPick,
  onOpenAgain,
  onCancel,
  onSkip,
}: {
  view: GateView | null;
  onPick: (method: SignInMethod) => void;
  onOpenAgain: () => void;
  onCancel: () => void;
  onSkip: () => void;
}) {
  return (
    <div className="fixed inset-0 z-[1000] flex flex-col overflow-hidden bg-black text-white select-none">
      <Tiles />
      <header data-tauri-drag-region="deep" className="relative flex h-(--titlebar-h,40px) shrink-0 items-center justify-end">
        <MuteButton />
        <WindowControls />
      </header>
      {view && (
        <main className="relative flex flex-1 items-center justify-center px-10 pb-10">
          <div className="flex w-full max-w-[960px] flex-col">{body(view, { onPick, onOpenAgain, onCancel, onSkip })}</div>
        </main>
      )}
    </div>
  );
}

function body(
  view: GateView,
  act: { onPick: (m: SignInMethod) => void; onOpenAgain: () => void; onCancel: () => void; onSkip: () => void },
) {
  if (view.kind === "waiting")
    return (
      <>
        <Label>Signing in with {METHOD[view.method]}</Label>
        <Heading>{view.finishing ? "Finishing sign-in." : "Finish signing in in your browser."}</Heading>
        <Cards>
          <Card icon={<Spinner />} label={view.finishing ? "Finishing sign-in" : "Waiting for your browser"} />
          {/* Too late to cancel once the browser is back: the site is
              already re-keying this machine's link. */}
          <Card icon={<OpenIcon />} label="Open again" onClick={view.finishing ? undefined : act.onOpenAgain} dim={view.finishing} />
          <Card icon={<CloseIcon />} label="Cancel" onClick={view.finishing ? undefined : act.onCancel} dim={view.finishing} />
        </Cards>
      </>
    );
  const { error, offline, revoked, emailOff, lastUsed } = view;
  const tag = (method: SignInMethod) => lastUsed === method && <LastUsed />;
  const failed = !offline && error;
  const label = failed ? failed : revoked ? "You've been signed out" : "Welcome to Wain";
  const heading = offline
    ? "Check your connection, or skip for now."
    : failed
      ? "Pick an account to try again."
      : revoked
        ? "Sign in again. Your agents are still running."
        : "Pick an account to sign in with.";
  return (
    <>
      <Label danger={Boolean(failed)}>{label}</Label>
      <Heading>{heading}</Heading>
      <Cards>
        <Card icon={<GitHubIcon />} label="GitHub" tag={tag("github")} corner onClick={() => act.onPick("github")} />
        <Card icon={<GoogleIcon />} label="Google" tag={tag("google")} corner onClick={() => act.onPick("google")} />
        {emailOff ? (
          <Card icon={<MailIcon />} label="Email" detail="Coming in the next few days" tag={tag("email")} off />
        ) : (
          <Card icon={<MailIcon />} label="Email" tag={tag("email")} corner onClick={() => act.onPick("email")} />
        )}
        {offline && <Card icon={<SkipIcon />} label="Skip for now" onClick={act.onSkip} />}
      </Cards>
    </>
  );
}

function Label({ children, danger = false }: { children: ReactNode; danger?: boolean }) {
  return (
    <div
      className={`flex items-center gap-2 pl-[102px] font-mono text-[11px] leading-[14px] tracking-[0.06em] uppercase max-lg:pl-0 ${danger ? "text-[#FF6467]" : "text-white/50"}`}
    >
      <Mark />
      {children}
    </div>
  );
}

function Heading({ children }: { children: ReactNode }) {
  return (
    <h1 className="mt-3.5 mb-10 pl-[102px] text-[36px] leading-10 font-light tracking-[-0.03em] text-white max-lg:pl-0">
      {children}
    </h1>
  );
}

function Cards({ children }: { children: ReactNode }) {
  return <div className="flex gap-[2px]">{children}</div>;
}

/// One card. Without `onClick` it only says something, like the waiting one;
/// `dim` greys out one that can't be used right now, and `off` fades a way in
/// that isn't open yet, leaving its `detail` and `tag` readable, as the site does.
function Card({
  icon,
  label,
  detail,
  tag,
  corner = false,
  dim = false,
  off = false,
  onClick,
}: {
  icon: ReactNode;
  label: string;
  detail?: string;
  tag?: ReactNode;
  corner?: boolean;
  dim?: boolean;
  off?: boolean;
  onClick?: () => void;
}) {
  const inner = (
    <>
      <span className={`flex items-start justify-between ${off ? "opacity-40" : ""}`}>
        {icon}
        {corner && <CornerArrow />}
      </span>
      <span className="flex flex-wrap items-end justify-between gap-x-3 gap-y-2">
        <span className="flex flex-col gap-0.5">
          <span className={`text-[17px] leading-6 tracking-[-0.01em] ${off ? "text-white/40" : "text-white/80"}`}>{label}</span>
          {detail && <span className="text-[13px] leading-[18px] text-white/40">{detail}</span>}
        </span>
        {/* Wraps under the label on a card too narrow for both, like the
            offline gate's four at the window's narrowest. */}
        {tag && <span className="ml-auto">{tag}</span>}
      </span>
    </>
  );
  const cls = `flex h-[220px] min-w-0 flex-1 basis-0 flex-col justify-between bg-[#1C1C1C] p-6 text-left ${dim ? "opacity-40" : ""}`;
  if (!onClick)
    return (
      <div aria-disabled={off || undefined} className={cls}>
        {inner}
      </div>
    );
  return (
    <button
      type="button"
      onClick={onClick}
      className={`${cls} cursor-pointer outline-none transition-colors hover:bg-[#242424] focus-visible:bg-[#242424] focus-visible:ring-1 focus-visible:ring-white/40`}
    >
      {inner}
    </button>
  );
}

/// The site's tag on the card this app last signed in with.
function LastUsed() {
  return (
    <span className="bg-white/10 px-1.5 py-[3px] font-mono text-[10px] leading-3 tracking-[0.06em] whitespace-nowrap text-white/70 uppercase">
      Last used
    </span>
  );
}

const MARK =
  "M4.81 0.11L5.76 0.00L33.04 0.03L34.57 0.24L35.85 0.60L37.61 1.39L39.16 2.36L40.18 3.24L41.07 4.19L42.05 5.47L42.81 6.74L43.75 8.78L57.50 36.83L57.54 37.08L57.05 38.10L49.30 53.66L35.85 81.08L35.59 81.10L34.25 78.39L32.84 75.33L31.16 72.02L28.27 65.90L21.18 51.36L20.38 49.58L19.22 47.28L18.06 44.73L17.37 43.46L15.96 40.40L8.06 23.90L0.36 8.02L0.04 6.74L0.00 5.47L0.14 4.45L0.63 3.17L1.31 2.15L1.94 1.50L2.45 1.09L3.47 0.55ZM134.59 0.11L135.55 0.02L141.41 0.01L162.57 0.02L163.34 0.11L164.36 0.37L165.38 0.83L166.40 1.59L166.91 2.15L167.46 2.92L167.94 3.94L168.24 5.21L168.28 6.23L168.25 6.74L168.09 7.51L167.74 8.53L158.20 28.16L149.15 47.03L148.23 48.81L140.49 64.88L139.56 66.66L136.41 73.29L135.47 75.08L133.29 79.67L132.49 81.20L132.21 80.94L129.81 76.10L128.73 73.80L127.80 72.02L122.62 61.31L110.72 37.08L110.77 36.83L113.78 30.71L126.27 5.72L126.80 4.96L128.08 3.43L128.66 2.88L129.94 1.89L130.79 1.39L131.98 0.82L133.51 0.32ZM83.08 18.47L84.55 18.45L86.33 18.62L87.61 18.86L88.63 19.15L89.90 19.63L91.43 20.40L92.96 21.44L93.98 22.26L95.51 23.88L96.09 24.59L97.11 26.12L98.14 27.91L105.76 43.20L128.23 89.10L127.98 89.61L127.19 90.63L125.86 92.03L124.33 93.23L122.54 94.32L120.76 95.07L118.97 95.59L117.70 95.84L115.66 96.00L110.81 96.00L109.03 95.81L106.99 95.33L106.22 95.08L104.95 94.57L103.93 94.06L102.91 93.47L101.89 92.76L100.36 91.47L99.02 90.12L97.51 88.08L96.76 86.81L86.88 66.66L86.33 66.01L85.82 65.60L85.06 65.22L84.04 65.01L83.53 65.04L83.02 65.17L82.25 65.51L81.47 66.15L80.93 66.92L79.49 69.98L71.07 87.06L70.29 88.34L69.25 89.74L68.45 90.63L67.39 91.65L66.45 92.48L64.92 93.55L64.15 93.99L61.86 95.02L60.07 95.57L58.80 95.83L57.01 95.98L52.93 96.00L52.17 95.99L50.13 95.78L48.09 95.33L46.56 94.80L45.03 94.09L44.01 93.50L42.99 92.79L41.71 91.68L40.44 90.25L39.81 89.36L39.78 89.10L40.36 87.83L43.07 82.47L45.74 76.86L47.18 74.06L52.38 63.35L55.32 57.48L65.77 36.06L68.69 30.20L70.15 27.40L70.91 26.12L71.97 24.59L73.04 23.32L74.86 21.63L76.64 20.40L78.17 19.63L79.45 19.15L81.49 18.65Z";

function Mark() {
  return (
    <svg width="18" height="10" viewBox="0 0 168.28 96" aria-hidden>
      <path d={MARK} fill="currentColor" />
    </svg>
  );
}

function CornerArrow() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden>
      <path d="M7 17 17 7M7 7h10v10" fill="none" stroke="#FFFFFF66" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

// Icons at 90%, the cards' labels at 80%: the picked Z1 frame.
const ICON = "#FFFFFFE6";

function GitHubIcon() {
  return (
    <svg width="40" height="40" viewBox="0 0 24 24" aria-hidden>
      <path
        fill={ICON}
        d="M12 .3a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 0-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.2.5-2.3 1.3-3.1-.2-.4-.6-1.6 0-3.2 0 0 1-.3 3.4 1.2a11.5 11.5 0 0 1 6 0c2.3-1.5 3.3-1.2 3.3-1.2.6 1.6.2 2.8 0 3.2.9.8 1.3 1.9 1.3 3.2 0 4.6-2.8 5.6-5.5 5.9.5.4.9 1 .9 2.2v3.3c0 .3.1.7.8.6A12 12 0 0 0 12 .3"
      />
    </svg>
  );
}

function GoogleIcon() {
  return (
    <svg width="40" height="40" viewBox="0 0 48 48" aria-hidden>
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 13 4 4 13 4 24s9 20 20 20 20-9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  );
}

function MailIcon() {
  return (
    <svg width="40" height="40" viewBox="0 0 24 24" aria-hidden>
      <path fill={ICON} d="M2 5h20v1.4l-10 6.4L2 6.4z" />
      <path fill={ICON} d="M2 8.8l10 6.4 10-6.4V19H2z" />
    </svg>
  );
}

function SkipIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" aria-hidden>
      <path d="M4 12h14M12 5l7 7-7 7" fill="none" stroke={ICON} strokeWidth="2" strokeLinecap="square" />
    </svg>
  );
}

function OpenIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" aria-hidden>
      <path d="M14 3h7v7M10 14 21 3M19 14v7H3V5h7" fill="none" stroke={ICON} strokeWidth="2" strokeLinecap="square" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" aria-hidden>
      <path d="M5 5l14 14M19 5 5 19" fill="none" stroke={ICON} strokeWidth="2" strokeLinecap="square" />
    </svg>
  );
}

function Spinner() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" className="animate-spin" aria-hidden>
      <circle cx="12" cy="12" r="9" fill="none" stroke="#FFFFFF33" strokeWidth="2" />
      <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke={ICON} strokeWidth="2" strokeLinecap="square" />
    </svg>
  );
}

/// The black-on-black tiles along the bottom, each striped like the site's.
/// `[x, y, fill]` on a 60px grid of a 1440×300 strip, the picked frame's own.
const TILES: [number, number, string][] = [
  ...pts("0 180,60 60,180 240,300 180,420 240,480 180,660 180,720 120,960 120,1020 180,1020 240,1080 240,1140 120,1140 240,1200 240,1260 120", "#121212"),
  ...pts("0 240,120 240,180 120,180 180,240 180,300 120,420 180,540 180,540 240,660 120,660 240,720 240,780 240,840 120,900 120,960 180,1260 240,1380 240", "#0C0C0C"),
  ...pts("60 180,60 240,240 240,300 240,360 60,360 240,600 180,600 240,840 180,840 240,900 240,1140 180,1260 60,1320 240", "#181818"),
  ...pts("480 240,960 240,1260 180", "#1F1F1F"),
];

function pts(list: string, fill: string): [number, number, string][] {
  return list.split(",").map((p) => {
    const [x, y] = p.split(" ").map(Number);
    return [x, y, fill];
  });
}

// Shared with What's New and onboarding so the brand's full-window pages read
// as one family.
export { Heading as GateHeading, Cards as GateCards };

function Tiles() {
  return (
    <svg
      aria-hidden
      width="1440"
      height="300"
      viewBox="0 0 1440 300"
      className="pointer-events-none absolute bottom-0 left-1/2 -translate-x-1/2"
    >
      <defs>
        <pattern id="gate-stripes" width="6" height="60" patternUnits="userSpaceOnUse">
          <rect width="2" height="60" fill="#00000080" />
        </pattern>
      </defs>
      {TILES.map(([x, y, fill]) => (
        <g key={`${x},${y}`}>
          <rect x={x} y={y} width="60" height="60" fill={fill} />
          <rect x={x} y={y} width="60" height="60" fill="url(#gate-stripes)" />
        </g>
      ))}
    </svg>
  );
}
