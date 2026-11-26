//! Each agent's newest usage reading on this server (#26): the 5-hour and
//! weekly windows Claude Code and Codex report while a turn runs. One per
//! harness, whichever session reported it, kept in `<home>/usage.json` so a
//! restart keeps the last ones. Clients get the list in `live_state` and a
//! `usage_changed` event; never a session's log, since it is no session's.
//! Each harness turns its own wire into a [`Reading`]; nothing here knows one.

use crate::{
    events::{now_rfc3339, rfc3339_from_unix},
    harness::Harness,
    sink::Sink,
    store,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::Mutex;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Reading {
    pub harness: Harness,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plan: Option<String>,
    /// A window is spent and the agent is refusing work.
    #[serde(default)]
    pub limited: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overage: Option<String>,
    #[serde(default)]
    pub using_overage: bool,
    /// When this server first received these figures: an identical reading
    /// after it changes nothing, so it moves only with them.
    #[serde(default)]
    pub at: String,
    #[serde(default)]
    pub windows: Vec<Window>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Window {
    /// `five_hour`, `weekly` or `other`.
    pub kind: String,
    /// 0-100.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub used_percent: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resets_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minutes: Option<u64>,
}

impl Window {
    /// A window `minutes` long, named by its length; `resets_at` in unix seconds.
    pub fn new(minutes: Option<u64>, used_percent: Option<f64>, resets_at: Option<i64>) -> Self {
        let kind = match minutes {
            Some(300) => "five_hour",
            Some(10080) => "weekly",
            _ => "other",
        };
        Self { kind: kind.into(), used_percent, resets_at: resets_at.map(rfc3339_from_unix), minutes }
    }
}

impl Reading {
    /// `harness`'s reading of `windows`, received now.
    pub fn new(harness: Harness, windows: Vec<Window>) -> Self {
        Self { harness, plan: None, limited: false, overage: None, using_overage: false, at: now_rfc3339(), windows }
    }
}

static READINGS: Mutex<Vec<Reading>> = Mutex::new(Vec::new());
static LOADED: tokio::sync::OnceCell<()> = tokio::sync::OnceCell::const_new();
/// Held from a change to its write, so clients and the file see changes in
/// the order they happened: each carries the whole list.
static WRITING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

async fn path() -> anyhow::Result<std::path::PathBuf> {
    Ok(store::get_home_app_dir().await?.join("usage.json"))
}

/// Reads `<home>/usage.json` once per process.
pub async fn load() {
    LOADED
        .get_or_init(|| async {
            let Ok(raw) = tokio::fs::read(path().await.unwrap_or_default()).await else { return };
            let list: Vec<Value> = serde_json::from_slice(&raw).unwrap_or_default();
            // One by one, so an entry this build cannot read costs that entry alone.
            let list = list.into_iter().filter_map(|v| serde_json::from_value(v).ok()).collect();
            *READINGS.lock().unwrap_or_else(|e| e.into_inner()) = list;
        })
        .await;
}

/// Every agent's newest reading, as `live_state` carries it.
pub fn readings() -> Vec<Reading> {
    READINGS.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Takes `reading` as its agent's newest, telling clients and the file
/// whenever it says something the last one did not.
pub async fn record(reading: Reading, sink: &Sink) {
    load().await;
    let _order = WRITING.lock().await;
    let Some(list) = note(reading) else { return };
    sink.emit("usage_changed", json!({ "usage": list })).ok();
    let written = match (path().await, serde_json::to_vec_pretty(&list)) {
        (Ok(path), Ok(body)) => store::write_atomic(&path, body).await,
        (Err(e), _) => Err(e),
        (_, Err(e)) => Err(e.into()),
    };
    if let Err(e) = written {
        eprintln!("[usage write err] {e:#}");
    }
}

/// [`replace`] on this process's list, answering the list where it changed.
fn note(reading: Reading) -> Option<Vec<Reading>> {
    let mut all = READINGS.lock().unwrap_or_else(|e| e.into_inner());
    replace(&mut all, reading).then(|| all.clone())
}

/// Puts `reading` in its agent's place. False where only `at` differs.
fn replace(all: &mut Vec<Reading>, reading: Reading) -> bool {
    match all.iter_mut().find(|r| r.harness == reading.harness) {
        Some(old) if Reading { at: reading.at.clone(), ..old.clone() } == reading => false,
        Some(old) => {
            *old = reading;
            true
        }
        None => {
            all.push(reading);
            true
        }
    }
}

#[cfg(test)]
pub(crate) fn note_for_test(reading: Reading) {
    note(reading);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn codex(used: f64) -> Reading {
        Reading::new(Harness::Codex, vec![Window::new(Some(300), Some(used), Some(1787957233))])
    }

    #[test]
    fn identical_figures_are_no_change() {
        let mut all = Vec::new();
        assert!(replace(&mut all, codex(6.0)));
        let mut later = codex(6.0);
        later.at = "2099-01-01T00:00:00.000Z".into();
        assert!(!replace(&mut all, later), "a new `at` alone is not a change");
        assert_ne!(all[0].at, "2099-01-01T00:00:00.000Z", "and leaves the first `at`");
        assert!(replace(&mut all, codex(7.0)));
        assert_eq!(all.len(), 1, "one reading per agent");
        assert_eq!(all[0].windows[0].used_percent, Some(7.0));

        let claude = Reading::new(Harness::ClaudeCode, Vec::new());
        assert!(replace(&mut all, claude));
        assert_eq!(all.len(), 2);
    }

    #[test]
    fn windows_are_named_by_length() {
        let kinds: Vec<String> = [Some(300), Some(10080), Some(43200), None]
            .into_iter()
            .map(|m| Window::new(m, None, None).kind)
            .collect();
        assert_eq!(kinds, ["five_hour", "weekly", "other", "other"]);
        assert_eq!(
            Window::new(Some(300), None, Some(1787915400)).resets_at.as_deref(),
            Some("2026-08-28T11:10:00.000Z")
        );
    }

    #[test]
    fn the_wire_shape_round_trips() {
        let reading = Reading { plan: Some("plus".into()), ..codex(6.0) };
        let wire = serde_json::to_value(&reading).unwrap();
        assert_eq!(wire["harness"], "codex");
        assert_eq!(wire["usingOverage"], false);
        assert_eq!(wire["windows"][0]["usedPercent"], 6.0);
        assert_eq!(wire["windows"][0]["kind"], "five_hour");
        assert!(wire.get("overage").is_none(), "absent, not null");
        assert_eq!(serde_json::from_value::<Reading>(wire).unwrap(), reading);
    }
}
