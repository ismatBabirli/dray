import { defineConfig } from "blume";
import { posthog, script } from "blume/analytics";

export default defineConfig({
  title: "Wain Docs",
  description: "How to install and use Wain, the desktop app for coding agents.",
  // The wordmark already says the name, so no text beside it. `href` leaves
  // the docs for the site, since `/` here is the docs' own index.
  logo: { image: "/logo.svg", text: "", href: "https://www.wainhq.com" },
  content: { root: "content" },
  // Dark first, like the site and the app. The palette is the site's: neutral
  // ramp, near-white accent, Geist.
  theme: {
    mode: "dark",
    accent: { light: "oklch(0.205 0 0)", dark: "oklch(0.922 0 0)" },
    background: { dark: "oklch(0.145 0 0)" },
    fonts: { display: "geist", body: "geist", mono: "geist-mono" },
  },
  // With no analytics adapter a rating goes nowhere, so asking for one is a
  // button that does nothing.
  feedback: false,
  // The site's PostHog project and settings (apps/web instrumentation-client.ts):
  // the same cookie, so a visitor moving between the site and the docs stays one
  // person, no autocapture, no recording. `/ingest` is the site's own
  // rewrite, reachable because the docs are served through wainhq.com.
  // `source` is registered through the snippet's queue, which replays before
  // the first pageview fires, so every docs event can be told from the site's.
  // The key is read at build: upstream's project key was written here, and a
  // fork that kept it sent its readers to upstream's analytics. Unset, none.
  analytics: process.env.DOCS_POSTHOG_KEY ? [
    posthog({
      key: process.env.DOCS_POSTHOG_KEY,
      host: "/ingest",
      ui_host: "https://us.posthog.com",
      persistence: "localStorage+cookie",
      autocapture: false,
      disable_session_recording: true,
      capture_pageview: "history_change",
      person_profiles: "identified_only",
    }),
    script({ content: 'posthog.register({ source: "docs" });' }),
  ] : [],
  agents: {
    llmsTxt: {
      details:
        "Wain is a free, open-source app for macOS, with a Linux beta, that runs coding-agent CLIs (Claude Code, Codex, pi, fx, Grok Build and OpenCode) in one chat window, many sessions at once, each optionally in its own git worktree. Bots are ongoing chats that start tasks and hear back from them. Download it from https://www.wainhq.com. Its `wain` command line (`curl -fsSL https://www.wainhq.com/install.sh | sh`) lets you or an agent create, list and message sessions, save drafts, link issues, share a dev server by public link and drive the built-in browser. Wain can also run headless on a Linux server and be driven from the Mac app. Reach for these docs to answer what Wain can do, where in the app a feature lives, and the exact steps, commands and flags.",
    },
  },
  github: { owner: "ismatbabirli", repo: "wain", dir: "apps/docs" },
  footer: {
    copyright: `© ${new Date().getFullYear()} Wain`,
    socials: { x: "https://x.com/yogesharc" },
  },
  // Served at wainhq.com/docs through a rewrite in apps/web. The content
  // folder is not named `docs`, or every page would land at /docs/docs/….
  deployment: { site: "https://www.wainhq.com", base: "/docs" },
});
