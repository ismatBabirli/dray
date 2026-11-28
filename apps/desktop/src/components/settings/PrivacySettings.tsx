import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useId, useState } from "react";

import SettingRow from "@/components/settings/SettingRow";
import { Switch } from "@/components/ui/switch";
import { setSurveysAllowed } from "@/lib/surveys";
import { invoke } from "@/lib/transport";
import type { PrivacySettings as Privacy } from "@/types/events";

const PRIVACY_URL = "https://www.wainhq.com/docs/reference/privacy";

/// Settings → Privacy: usage data and crash reports, both on by default.
///
/// Drawn from what Rust answers after each write, never optimistically, so a
/// failed write leaves the switch where the file is. Disabled until the first
/// read lands rather than guessing either value.
export default function PrivacySettings() {
  const [view, setView] = useState<Privacy | null>(null);
  const usageId = useId();
  const crashId = useId();

  useEffect(() => {
    invoke<Privacy>("privacy_settings")
      .then(setView)
      .catch((e) => console.error("[privacy read]", e));
  }, []);

  const save = async (usage: boolean, crashReports: boolean) => {
    try {
      setView(await invoke<Privacy>("set_privacy_settings", { usage, crashReports }));
      void setSurveysAllowed(usage);
    } catch (e) {
      console.error("[privacy write]", e);
    }
  };

  const locked = view?.lockedBy;
  // Off and disabled under the environment, never the stored value: a switch
  // drawn on while nothing is sent would be the one lie on this page.
  const lockedNote = locked && (
    <>
      Turned off for this run by <code className="font-mono">{locked}</code>.
    </>
  );

  return (
    <>
      <SettingRow
        id={usageId}
        label="Share usage data"
        description={lockedNote || "Launches, which features get used and which agents run, counted under a random id."}
      >
        <Switch
          id={usageId}
          disabled={!view || !!locked}
          checked={!locked && (view?.usage ?? false)}
          onCheckedChange={(on) => view && void save(on, view.crashReports)}
        />
      </SettingRow>
      <SettingRow
        id={crashId}
        label="Send crash reports"
        description={lockedNote || "When Wain breaks, the version and the place in its own code. Never the error's text."}
      >
        <Switch
          id={crashId}
          disabled={!view || !!locked}
          checked={!locked && (view?.crashReports ?? false)}
          onCheckedChange={(on) => view && void save(view.usage, on)}
        />
      </SettingRow>
      <p className="text-ui text-muted-foreground">
        The{" "}
        <button
          type="button"
          className="text-foreground underline underline-offset-2"
          onClick={() => void openUrl(PRIVACY_URL)}
        >
          privacy policy
        </button>{" "}
        lists every field Wain sends, and what it never sends.
      </p>
    </>
  );
}
