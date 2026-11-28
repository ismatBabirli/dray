import { mockIPC } from "@tauri-apps/api/mocks";
import React, { useEffect, useState } from "react";
import ReactDOM from "react-dom/client";

import PrivacySettings from "@/components/settings/PrivacySettings";
import { TooltipProvider } from "@/components/ui/tooltip";
import DemoThemeBar from "@/demo/ThemeBar";
import type { PrivacySettings as Privacy } from "@/types/events";
import "../App.css";

/// Settings → Privacy with Rust stubbed: the switches write to a copy held
/// here, and `?locked=WAIN_NO_ANALYTICS` (or `DO_NOT_TRACK`) draws the run
/// the environment turned off. The log under the page is what Rust was asked.

const locked = new URLSearchParams(location.search).get("locked");
let stored: Privacy = { usage: true, crashReports: true, lockedBy: locked };
const listeners = new Set<(line: string) => void>();
const log = (line: string) => listeners.forEach((l) => l(line));

mockIPC(async (cmd, args) => {
  const call = cmd === "server_invoke" ? (args as { cmd: string; args: Record<string, unknown> }) : { cmd, args: args as Record<string, unknown> };
  if (call.cmd === "list_servers") return [];
  if (call.cmd === "privacy_settings") return stored;
  if (call.cmd === "set_privacy_settings") {
    const { usage, crashReports } = call.args as { usage: boolean; crashReports: boolean };
    stored = { ...stored, usage, crashReports };
    log(`set_privacy_settings usage=${usage} crashReports=${crashReports}`);
    return stored;
  }
  if (call.cmd === "analytics_identity") return null;
  return null;
});

function Demo() {
  const [lines, setLines] = useState<string[]>([]);
  useEffect(() => {
    const add = (line: string) => setLines((l) => [...l, line]);
    listeners.add(add);
    return () => void listeners.delete(add);
  }, []);
  return (
    <TooltipProvider>
      <DemoThemeBar />
      <main className="mx-auto flex max-w-[640px] flex-col gap-7 p-10">
        <header className="flex flex-col gap-1.5">
          <h1 className="text-xl font-semibold">Privacy</h1>
          <p className="text-ui text-muted-foreground">
            What Wain sends to help fix and improve it. Your prompts, code and files never leave your machine.
          </p>
        </header>
        <section className="flex flex-col gap-4">
          <PrivacySettings />
        </section>
        <pre data-testid="log" className="text-xs text-muted-foreground">{lines.join("\n") || "no writes yet"}</pre>
      </main>
    </TooltipProvider>
  );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Demo />
  </React.StrictMode>,
);
