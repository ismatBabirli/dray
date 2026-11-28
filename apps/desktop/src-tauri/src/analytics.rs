//! Anonymous usage analytics over PostHog.
//!
//! A launch, a day the app was used, a session starting, a feature being
//! used, something breaking, a bot made and a routine set up — carrying no
//! content and no identity beyond a random id minted on this machine. What they answer is how many people run Wain, on which version,
//! whether they come back, which of the things built here anybody actually
//! uses, and whether the build is failing under them in a way nothing else
//! would ever tell us.
//!
//! **Two switches, both on by default** (Settings → Privacy): usage data
//! (`analytics_enabled`) and crash reports (`crash_reports_enabled`), read from
//! `settings.json` on every send, so the app and the Mac's background server
//! obey a change at once. `WAIN_NO_ANALYTICS` or `DO_NOT_TRACK` turns both off
//! for the run. The install id is minted on first use by
//! [`settings::ensure_install_id`] and cleared when both switches go off. A uuid
//! v4 rather than the v7 used for session ids elsewhere: v7 embeds the moment
//! it was minted, which for an identifier meant to say nothing is one more
//! thing it says.
//!
//! **No transport plugin.** `reqwest` is already here for Linear, and PostHog's
//! capture API is one POST, so an event is a request rather than a queue with a
//! flush interval. At this volume — single figures per session — batching would
//! buy nothing and cost a background task and a drain on the quit path.
//!
//! **Nothing is stamped for us.** Aptabase's plugin put `appVersion`, `osName`
//! and friends on every envelope itself; PostHog does not, so
//! [`base_properties`] builds that set once. Without it version adoption — the
//! one question the old single-event setup could answer — would be lost.
//!
//! The project key is compiled in from `POSTHOG_KEY`. An absent key is the
//! ordinary case rather than a failure: every local build compiles with none
//! and sends nothing, which is what keeps `pnpm tauri dev` out of the numbers.

use std::collections::BTreeMap;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use serde::Serialize;
use serde_json::{json, Map, Value};
use ts_rs::TS;

use crate::harness::Harness;
use crate::settings;
use crate::store::SessionIndexItem;

/// Set at build time by the release workflow. `option_env!` resolves at compile
/// time, so `build.rs` has to declare the rerun — otherwise a key exported
/// after the first build stays baked in as absent.
const API_KEY: Option<&str> = option_env!("POSTHOG_KEY");

/// Set at build time only if the project moves off US cloud. Wrong host means a
/// key that authenticates nowhere and events that vanish with a 401, so it is
/// worth a knob rather than a constant somebody has to remember to edit.
const HOST_OVERRIDE: Option<&str> = option_env!("POSTHOG_HOST");

const DEFAULT_HOST: &str = "https://us.i.posthog.com";

/// Where events go.
///
/// The empty string is treated as unset, and that is not defensive: the release
/// workflow passes this through from a repository *variable*, which expands to
/// `""` when undefined rather than being absent — so a `Some("")` here is the
/// ordinary case for every build that has not set one, and taking it literally
/// would post every event at a URL with no host in it.
fn host() -> &'static str {
    host_of(HOST_OVERRIDE)
}

fn host_of(over: Option<&'static str>) -> &'static str {
    over.filter(|host| !host.is_empty()).unwrap_or(DEFAULT_HOST)
}

/// The compiled-in key, where one is; empty reads as absent.
fn api_key() -> Option<&'static str> {
    API_KEY.filter(|key| !key.is_empty())
}

/// Short. Nothing waits on this, and a request still in flight when the app
/// quits is a dropped event either way — so the only thing a long timeout buys
/// is a task outliving the thing it was reporting about.
const TIMEOUT: Duration = Duration::from_secs(10);

/// The variable that turned reporting off for this run, if one did.
///
/// `DO_NOT_TRACK` is the shared convention many CLIs honour; `0` or empty reads
/// as unset, since some shells export it that way to mean "track".
fn env_lock() -> Option<&'static str> {
    if std::env::var_os("WAIN_NO_ANALYTICS").is_some() {
        return Some("WAIN_NO_ANALYTICS");
    }
    std::env::var("DO_NOT_TRACK")
        .is_ok_and(|v| !v.is_empty() && v != "0")
        .then_some("DO_NOT_TRACK")
}

fn env_opt_out() -> bool {
    env_lock().is_some()
}

/// Crash events answer to the crash switch; everything else to usage.
fn is_crash(event: &str) -> bool {
    matches!(event, "error" | "$exception")
}

/// Whether `event` may go: the environment, then its switch, read fresh.
async fn consented(event: &str) -> bool {
    !env_opt_out()
        && settings::read_checked()
            .await
            .is_some_and(|s| if is_crash(event) { s.crash_reports_enabled } else { s.analytics_enabled })
}

/// Settings → Privacy, as drawn: the stored switches, and the variable that
/// overrides both for this run.
#[derive(Debug, Clone, Serialize, TS)]
#[ts(export, export_to = "events.ts")]
#[serde(rename_all = "camelCase")]
pub struct PrivacySettings {
    pub usage: bool,
    pub crash_reports: bool,
    pub locked_by: Option<String>,
}

fn privacy_view(settings: &settings::AppSettings) -> PrivacySettings {
    PrivacySettings {
        usage: settings.analytics_enabled,
        crash_reports: settings.crash_reports_enabled,
        locked_by: env_lock().map(str::to_string),
    }
}

#[cfg_attr(feature = "desktop", tauri::command)]
pub async fn privacy_settings() -> PrivacySettings {
    privacy_view(&settings::read().await)
}

/// Saves both switches. With both off the install id goes too, so nothing on
/// disk names an install that asked not to be counted; turning one back on
/// mints a fresh id, a new person, which is honest about the gap.
#[cfg_attr(feature = "desktop", tauri::command)]
pub async fn set_privacy_settings(usage: bool, crash_reports: bool) -> Result<PrivacySettings, String> {
    let saved = settings::update(|s| {
        s.analytics_enabled = usage;
        s.crash_reports_enabled = crash_reports;
        if !usage && !crash_reports {
            s.install_id = None;
        }
    })
    .await
    .map_err(|e| format!("{e:#}"))?;
    Ok(privacy_view(&saved))
}

/// What the webview needs to speak to PostHog for itself.
///
/// Handed over whole rather than looked up on the other side: the answer to
/// "may I", "as whom" and "where to" is one value, and its absence is the
/// refusal.
#[derive(Debug, Clone, Serialize, TS)]
#[ts(export, export_to = "events.ts")]
#[serde(rename_all = "camelCase")]
pub struct SurveyIdentity {
    pub key: String,
    pub host: String,
    /// The install id, so the SDK and this module are one person in PostHog
    /// rather than two. Bootstrapped on the other side, never `identify`d into
    /// existence — a person is already what the POSTs create.
    pub distinct_id: String,
    /// [`base_properties`], to be `$set` as **person** properties on the other
    /// side. Event properties are what this module sends and what surveys
    /// cannot target on, so without this the SDK arrives and the reason for
    /// wanting it — targeting a survey at a version or an OS — still does not
    /// work.
    #[ts(type = "Record<string, string | number | boolean>")]
    pub person_properties: Map<String, Value>,
}

/// Who the webview may report as, or `None` where it may not report at all.
///
/// The SDK on the other side exists for **surveys**, which are drawn by
/// `posthog-js` and by nothing else — there is no way to render one from here.
/// It captures no events of its own. `None` on the grounds [`send`] refuses a
/// usage event on — no key compiled in, the environment, or the usage switch
/// off — plus an install id that could not be persisted.
#[cfg_attr(feature = "desktop", tauri::command)]
pub async fn analytics_identity() -> Option<SurveyIdentity> {
    // Same order as `send`: no key compiled in is the ordinary case for a local
    // build, and checking it first keeps a build that sends nothing from
    // reading the settings file to find that out.
    let key = api_key()?;

    // Surveys answer to the usage switch: a survey is a usage question.
    if env_opt_out() || !settings::read_checked().await?.analytics_enabled {
        return None;
    }

    let mut person_properties = base_properties().clone();

    // How many sessions this install has ever held, so a survey can be aimed at
    // somebody who has used Wain enough to have an opinion of it. PostHog has
    // no other way to know — nothing it receives counts sessions, and the index
    // is the only place the answer lives.
    //
    // Added here rather than folded into `base_properties`, which is a
    // `OnceLock` answering once for the life of the process where this moves
    // every time a session is made. A failed read leaves the property absent,
    // which a survey targeting a minimum reads as **not** matching — the safe
    // direction, since the cure is opening the app again.
    if let Ok(sessions) = crate::store::read_index().await {
        person_properties.insert("session_count".into(), sessions.len().into());
    }

    Some(SurveyIdentity {
        key: key.to_string(),
        host: host().to_string(),
        distinct_id: settings::ensure_install_id().await?,
        person_properties,
    })
}

/// Enqueues one event, or drops it where its switch or the environment says no.
///
/// Deliberately **not** `async` and takes no `AppHandle`: an event is
/// fire-and-forget, and a call that had to be awaited would put a file read and
/// an HTTPS request in front of whatever the reader just did. That is also what
/// lets the sites that report features call this — several are synchronous
/// commands with no handle in reach.
///
/// The switches and the environment are read inside the spawned half, on every
/// call, so a new call site cannot forget to ask.
///
/// `event` is `&'static str` because every one is a literal, and taking it by
/// value is what keeps the spawned future `'static` without an allocation.
pub fn track(event: &'static str, properties: Value) {
    crate::spawn(send(event, None, properties));
}

/// Reports `event` at most once per local day per `key`, for the life of this
/// process.
///
/// **Deliberately not persisted, and that is the whole design.** PostHog counts
/// distinct people per day, so an install reporting the same event three times
/// in one day still reads as one active user — a restart re-reporting costs one
/// event and moves no number, where remembering the date across runs would cost
/// a file, a lock and a corruption path on the launch path to prevent nothing.
///
/// **The day is claimed only once an event can actually go**, inside [`send`]
/// and after the install id is in hand — never here, where the spawn happens.
/// Claimed up front, a run whose id write failed would claim the day, send
/// nothing, and silence itself until midnight.
///
/// Known wrinkle, not worth solving: "day" is the machine's local date, which
/// disagrees with PostHog's project timezone at the edges for anyone outside
/// it.
pub fn track_daily(event: &'static str, key: String, properties: Value) {
    crate::spawn(send(event, Some(key), properties));
}

/// Whether `key` still owes a report for `day`, marking it reported if so.
///
/// Split out so the throttle can be tested without a clock or a request, and so
/// the lock is visibly released before anything is sent. Atomic under that
/// lock, which is what stops two events landing together from both claiming.
fn claim_day(key: String, day: String) -> bool {
    static REPORTED: Mutex<BTreeMap<String, String>> = Mutex::new(BTreeMap::new());

    // Recovered rather than unwrapped: a poisoned lock is not a reason to take
    // the app down over an event nobody is waiting on.
    let mut reported = REPORTED.lock().unwrap_or_else(|e| e.into_inner());
    if reported.get(&key).is_some_and(|last| *last == day) {
        return false;
    }
    reported.insert(key, day);

    true
}

/// Reports that this install was used today, at most once a day per run.
///
/// Neither event beside it answers activity. `app_started` measures installs
/// and version adoption, since this app is left open for days at a time, and
/// `session_started` fires only for a session being *created* — so somebody
/// working all day in one resumed session was invisible, and the most engaged
/// readers read as churned.
///
/// Three call sites, each covering a hole the others leave. **Launch** is the
/// only one guaranteed to fire: `focus.ts` seeds itself from
/// `document.hasFocus()` and reports changes alone, so a window that comes up
/// already frontmost never reports *gaining* focus and somebody who opens Wain,
/// works and quits without switching apps would go uncounted. **Focus gained**
/// catches coming back to check on a session an agent is running, which reaches
/// no prompt at all and is real use of an app about parallel agents. **The
/// `send_msg` command** covers a reader who leaves the app open and frontmost
/// across a date boundary — the *command*, not `SessionManager::send_msg` one
/// call down, since the orchestration socket reaches that directly to relay a
/// `wain session send` and to start a session `wain session new` asked for.
/// Only a client somebody is typing into reaches the command — the app, the
/// island, a phone — and one that counts for itself is skipped
/// ([`client_counts`]).
///
/// The throttle is what makes a third site free rather than a third event: all
/// three share one key, so whichever gets there first claims the day and the
/// other two are no-ops. It is also why none of them asks what the others did
/// — "report this only if nothing reported today" is exactly what the claim
/// already is.
///
/// A command too, for the focus half: the signal comes from `src/lib/focus.ts`,
/// which is where the rule for reading it lives — the DOM's `focus` fires for a
/// native menu or devtools closing too, which is not the reader arriving.
#[cfg_attr(feature = "desktop", tauri::command)]
pub fn track_active_day() {
    track_daily("active_day", "active_day".into(), json!({}));
}

/// Reports a feature being reached for.
///
/// One event carrying the feature as a property, never an event per feature:
/// PostHog breaks a single insight down by property, where a name each is a
/// chart each to keep in step — and a feature added later then shows up in the
/// existing breakdown rather than needing a dashboard change to be visible at
/// all.
///
/// Reported on the feature *working*, not on the control being pressed. A click
/// that errored says nothing about adoption.
pub fn feature_used(feature: &'static str) {
    track("feature_used", json!({ "feature": feature }));
}

tokio::task_local! {
    /// Set around a serve call from a Wain app that reports the sessions it
    /// starts on this server itself, which it says in its hello.
    pub static CLIENT_COUNTS: bool;
}

/// Whether the call being served came from an app that reports what it
/// starts here, so this process must not report it a second time under its
/// own install id. False outside a serve call: the composer on this machine,
/// an agent's `wain new`, a phone.
pub fn client_counts() -> bool {
    CLIENT_COUNTS.try_with(|counts| *counts).unwrap_or(false)
}

/// Reports a session this process just wrote down, on this machine. Whether
/// it is a bot's is a few file reads, so it is worked out in the spawned half
/// rather than in front of the create.
pub fn session_started(item: &SessionIndexItem) {
    let item = item.clone();
    crate::spawn(async move {
        let bot = crate::bots::bot_at(&item.cwd).await.is_some();
        let role = BotRole { bot, by_bot: !bot && crate::bots::in_bot_tree(&item).await };
        send("session_started", None, session_properties(&item, role, None)).await;
    });
}

/// Reports a session the reader's app just started on an external server.
/// `os` is what the server's welcome said, `None` from one too old to say.
///
/// The app owns this count rather than the server: a Linux `wain-serve`
/// carries no key and sends nothing, and a remote Mac would count it under
/// its own install as a local session of somebody else.
///
/// `bot` is whether it runs in one of that server's bot folders. The app only
/// starts a session there from the composer or New bot, neither of which has
/// a parent, so it is never `by_bot`.
pub fn remote_session_started(item: &SessionIndexItem, os: Option<&str>, bot: bool) {
    track("session_started", session_properties(item, BotRole { bot, by_bot: false }, Some(os)));
}

/// What a session is to bots.
#[derive(Debug, Clone, Copy, Default)]
struct BotRole {
    /// Runs in a bot's folder: its chat, or a routine's run.
    bot: bool,
    /// Started under a bot's session, at any depth, as its tasks are.
    by_bot: bool,
}

/// `session_started`'s properties. Read off the index entry, which is what was
/// actually written down; nothing about the prompt, the path or the server,
/// whose OS goes out only as a closed tag since the welcome is the server's
/// own text.
fn session_properties(item: &SessionIndexItem, role: BotRole, remote: Option<Option<&str>>) -> Value {
    let mut props = json!({
        "harness": item.harness,
        "model": item.model.as_str(),
        "effort": item.effort,
        "permission_mode": item.permission_mode,
        "fast": item.fast,
        "worktree": item.worktree_name.is_some(),
        "spawned": item.parent_session_id.is_some(),
        "bot": role.bot,
        "by_bot": role.by_bot,
        // A routine's run is a bot's session too; without this, a routine on a
        // short schedule would drown out the chats people actually open.
        "routine": item.routine_run.is_some(),
        "location": if remote.is_some() { "remote" } else { "local" },
    });
    if let Some(os) = remote {
        props["remote_os"] = match os {
            Some("macos") => "macos",
            Some("linux") => "linux",
            Some(_) => "other",
            None => "unknown",
        }
        .into();
    }
    props
}

/// Reports a bot made: `via` `app` from New bot (desktop or phone), `cli`
/// from `wain bot new`. The harness rides only where it is known: a bot made
/// from the CLI gets its agent at its first message, and that chat's
/// `session_started` (`bot: true`) says which.
pub fn bot_created(harness: Option<Harness>, via: &'static str) {
    let mut props = json!({ "via": via });
    if let Some(harness) = harness {
        props["harness"] = json!(harness);
    }
    track("bot_created", props);
}

/// Reports `bot_message` where `session_id` is a bot's chat. Called from the
/// `send_msg` command alone, which only somebody pressing send reaches; a
/// bot's message to another bot, a task's report and a routine's prompt all
/// reach the session manager directly.
pub fn message_sent(session_id: String) {
    crate::spawn(async move {
        let Ok(Some(item)) = crate::store::get_session_index_item(&session_id).await else { return };
        if item.routine_run.is_none() && crate::bots::bot_at(&item.cwd).await.is_some() {
            send("feature_used", None, json!({ "feature": "bot_message" })).await;
        }
    });
}

/// Reports a routine a bot just set up: which kind of schedule, never its
/// times, and whether it has a check.
pub fn routine_added(every: bool, check: bool) {
    track("routine_added", json!({ "schedule": if every { "every" } else { "at" }, "check": check }));
}

/// Reports something that broke, by **where** it broke and never by what it
/// said.
///
/// One event with the kind as a property, the bargain [`feature_used`] makes,
/// so a fourth kind later shows up in the existing breakdown rather than
/// needing a dashboard change to be visible at all.
///
/// The rule every call site here has to keep: an error string or a stack frame
/// carries file paths, and a path carries the project, the branch and the
/// client's name. The settings dialog promises prompts, code and conversations
/// are never collected, so `properties` may hold a closed set of tags — a
/// stage, a harness, a `file:line` of our own source — and never a `String`
/// that came out of an error.
pub fn error(kind: &'static str, properties: Value) {
    track("error", error_properties(kind, properties));
}

/// Reports a crash to PostHog Error Tracking as an `$exception`: the
/// [`error`] rule holds, so `value` is a fixed phrase per kind and never the
/// error's own message, and every frame is our own code.
///
/// Frames go outermost first, the order Error Tracking draws them in; `custom`
/// frames, since a minified bundle frame has no source map to resolve against
/// and a Rust `Location` needs none.
pub fn exception(kind: &'static str, error_type: &str, value: &str, frames: Vec<Value>, properties: Value) {
    track("$exception", exception_properties(kind, error_type, value, frames, properties));
}

fn exception_properties(kind: &'static str, error_type: &str, value: &str, frames: Vec<Value>, properties: Value) -> Value {
    let mut props = error_properties(kind, properties);
    props["$exception_list"] = json!([{
        "type": error_type,
        "value": value,
        "mechanism": { "handled": false, "synthetic": false },
        "stacktrace": { "type": "raw", "frames": frames },
    }]);
    props
}

/// One frame of our own code in Error Tracking's `custom` shape.
pub fn frame(lang: &str, function: &str, file: &str, line: Option<u32>, col: Option<u32>) -> Value {
    json!({
        "platform": "custom",
        "lang": lang,
        "function": function,
        "filename": file,
        "lineno": line,
        "colno": col,
        "resolved": true,
        "in_app": true,
    })
}

/// Frames from the webview, `name@bundle.js:line:col` innermost first, as
/// Error Tracking frames outermost first. Anything spelled outside that
/// alphabet is dropped, so a path or message text cannot ride along.
pub fn bundle_frames(frames: Vec<String>) -> Vec<Value> {
    let mut out: Vec<Value> = frames
        .iter()
        .filter(|f| {
            f.len() <= 120
                && f.contains(".js:")
                && f.chars().all(|c| c.is_ascii_alphanumeric() || "_$.@:-".contains(c))
        })
        .take(8)
        .filter_map(|f| {
            let (function, rest) = f.split_once('@')?;
            let mut parts = rest.rsplitn(3, ':');
            let col = parts.next()?.parse().ok();
            let line = parts.next()?.parse().ok();
            let file = parts.next()?;
            Some(frame("javascript", function, file, line, col))
        })
        .collect();
    out.reverse();
    out
}

/// The merge [`error`] sends, split out because it is the one part of that call
/// a test can hold: the kind goes in **last**, so a call site carrying one of
/// its own cannot rename what the breakdown is read by. The opposite of
/// [`track`]'s rule, where a call site correcting a base property is the point.
fn error_properties(kind: &'static str, properties: Value) -> Value {
    let mut props = Map::new();
    if let Value::Object(extra) = properties {
        props.extend(extra);
    }
    props.insert("kind".into(), kind.into());

    Value::Object(props)
}

/// Reports panics by location, and leaves what a panic *does* alone.
///
/// Two closed things go out: `file:line` from the panic's own `Location`, and
/// the thread's name, which is one this app or tokio chose. **The payload never
/// does** — a panic message is arbitrary text, and `expect` is routinely handed
/// a path to explain itself with.
///
/// Chained to the previous hook rather than replacing it, so the default
/// printing and whatever the profile does about aborting are unchanged.
/// Fire-and-forget like every other event: a panic on the main thread takes the
/// process before the request could land, which is a dropped event and not a
/// reason to hold a dying app open.
pub fn install_panic_hook() {
    let previous = std::panic::take_hook();

    std::panic::set_hook(Box::new(move |info| {
        let thread = std::thread::current().name().unwrap_or("unnamed").to_string();
        let at = info.location().map(|at| (trim_source_path(at.file()), at.line(), at.column()));
        let frames = at
            .map(|(file, line, col)| vec![frame("rust", &thread, file, Some(line), Some(col))])
            .unwrap_or_default();
        exception(
            "panic",
            "panic",
            &at.map_or("panic".into(), |(file, line, _)| format!("panic at {file}:{line}")),
            frames,
            json!({
                "location": at.map(|(file, line, _)| format!("{file}:{line}")),
                "thread": thread,
            }),
        );

        previous(info);
    }));
}

/// Cuts the build machine out of a panic's source path.
///
/// A `Location` is baked in at compile time, so it names wherever this was
/// built and never the reader's disk — this crate's own code reports
/// `src/session.rs`, but a dependency reports the release runner's home
/// directory on the way to the cargo registry, and the app's own path on a
/// local build. Cargo's `trim-paths` is the proper cure and is not stable on
/// the toolchain the release workflow pins, so the report trims instead: a
/// registry or git checkout keeps the part naming the crate, and anything else
/// still absolute is cut to its file name, since an absolute path arriving here
/// came from a build directory.
fn trim_source_path(file: &str) -> &str {
    for marker in ["/registry/src/", "/git/checkouts/"] {
        if let Some((_, crate_path)) = file.split_once(marker) {
            return crate_path;
        }
    }

    if file.starts_with('/') {
        return file.rsplit('/').next().unwrap_or(file);
    }

    file
}

/// The body of [`track`], split out so the spawn site stays one line.
///
/// Best-effort throughout, like the notification path next door: analytics that
/// surfaced an error would be worse than analytics that went missing. A
/// non-success status is logged rather than dropped, since the two ways this
/// silently reports nothing — a wrong key and a wrong region — both land there.
async fn send(event: &'static str, daily_key: Option<String>, properties: Value) {
    let Some(key) = api_key() else {
        // A dev build has no key, so this is the only way to see what it would send.
        if cfg!(debug_assertions) && consented(event).await {
            eprintln!("[analytics] would send {event} {properties}");
        }
        return;
    };

    if !consented(event).await {
        return;
    }

    let Some(distinct_id) = settings::ensure_install_id().await else {
        return;
    };

    // After the id, never before it: see `track_daily`.
    if let Some(daily_key) = daily_key {
        if !claim_day(daily_key, chrono::Local::now().format("%Y-%m-%d").to_string()) {
            return;
        }
    }

    let mut props = base_properties().clone();
    // PostHog judges bot traffic at query time off this *property*, never the
    // request's User-Agent header, and reads a missing one as automation — so
    // without it every app event is `$virt_is_bot` and bot-filtered insights
    // drop the app silently. Here rather than in `base_properties`, which is
    // also `$set` on the person.
    props.insert(
        "$raw_user_agent".into(),
        format!(
            "Wain/{} ({}; {})",
            env!("CARGO_PKG_VERSION"),
            std::env::consts::OS,
            std::env::consts::ARCH
        )
        .into(),
    );
    if let Value::Object(extra) = properties {
        props.extend(extra);
    }

    let body = json!({
        "api_key": key,
        "event": event,
        "distinct_id": distinct_id,
        "properties": props,
    });

    let endpoint = format!("{}/i/v0/e/", host());

    let request = crate::http().post(&endpoint).timeout(TIMEOUT).json(&body);
    match request.send().await {
        Ok(response) if !response.status().is_success() => {
            eprintln!("[analytics err] {} from {endpoint}", response.status());
        }
        Err(e) => eprintln!("[analytics err] {e}"),
        Ok(_) => {}
    }
}

/// What every event carries, built once.
///
/// Deliberately short. The OS *version* is absent because nothing in the tree
/// knows it — reading it means a new dependency or spawning `sw_vers` on the
/// launch path, and neither is worth a figure nobody has asked a question of
/// yet. `arch` is free from the same module and does answer one, since Apple
/// Silicon is what decides the transcription backend.
fn base_properties() -> &'static Map<String, Value> {
    static BASE: OnceLock<Map<String, Value>> = OnceLock::new();

    BASE.get_or_init(|| {
        let mut props = Map::new();
        props.insert("app_version".into(), env!("CARGO_PKG_VERSION").into());
        props.insert("os".into(), std::env::consts::OS.into());
        props.insert("arch".into(), std::env::consts::ARCH.into());
        // Only reachable by a debug build compiled *with* a key, which is not
        // how anything ships — but that is exactly the build whose events would
        // otherwise be indistinguishable from a release one's.
        props.insert("is_debug".into(), cfg!(debug_assertions).into());
        // The marketing site reports into this same project under a *cookieless
        // per-visit* id where this one is a stable install uuid, so any
        // unfiltered "unique users" figure is the sum of two incompatible
        // populations. `$lib` half-separates them already — posthog-js sets it
        // and this POST sets nothing — but a dashboard built on a property's
        // *absence* breaks the day something else stops setting one. The one
        // thing here that cannot be added retroactively.
        props.insert("source".into(), "app".into());
        props
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item() -> SessionIndexItem {
        use crate::{events::ApprovalPolicy, harness::Harness, models::ModelId};
        SessionIndexItem::new(
            "s", Harness::ClaudeCode, "/p", "/p", None, None, "hi",
            ModelId::new("opus"), None, ApprovalPolicy::Auto, false, None,
        )
    }

    /// One owner per session: a serve call from an app that counts its own
    /// sessions is the only place this process stays quiet.
    #[tokio::test]
    async fn only_a_counting_client_silences_the_server() {
        assert!(!client_counts(), "the composer on this machine, an agent's `wain new`");
        assert!(CLIENT_COUNTS.scope(true, async { client_counts() }).await);
        assert!(!CLIENT_COUNTS.scope(false, async { client_counts() }).await, "a phone");
    }

    /// The server's OS is its own text, so only closed tags leave the machine.
    #[test]
    fn location_is_closed_tags() {
        let none = BotRole::default();
        let local = session_properties(&item(), none, None);
        assert_eq!(local["location"], json!("local"));
        assert!(local.get("remote_os").is_none());
        assert_eq!(local["harness"], json!("claude_code"));

        let tag = |os| session_properties(&item(), none, Some(os))["remote_os"].clone();
        assert_eq!(tag(Some("linux")), json!("linux"));
        assert_eq!(tag(Some("macos")), json!("macos"));
        assert_eq!(tag(Some("my-hostname")), json!("other"));
        assert_eq!(tag(None), json!("unknown"));
        assert_eq!(session_properties(&item(), none, Some(None))["location"], json!("remote"));
    }

    /// A bot's chat, a routine's run and a bot's task each read apart, and an
    /// ordinary session reads as none of them.
    #[test]
    fn a_session_says_what_it_is_to_bots() {
        let flags = |props: Value| (props["bot"].clone(), props["by_bot"].clone(), props["routine"].clone());
        let (no, yes) = (json!(false), json!(true));

        let plain = session_properties(&item(), BotRole::default(), None);
        assert_eq!(flags(plain), (no.clone(), no.clone(), no.clone()));

        let chat = session_properties(&item(), BotRole { bot: true, by_bot: false }, None);
        assert_eq!(flags(chat), (yes.clone(), no.clone(), no.clone()));

        let mut run = item();
        run.routine_run = Some("r1".into());
        let run = session_properties(&run, BotRole { bot: true, by_bot: false }, None);
        assert_eq!(flags(run), (yes.clone(), no.clone(), yes.clone()));

        let task = session_properties(&item(), BotRole { bot: false, by_bot: true }, None);
        assert_eq!(flags(task), (no.clone(), yes.clone(), no.clone()));

        let remote = session_properties(&item(), BotRole { bot: true, by_bot: false }, Some(Some("linux")));
        assert_eq!(remote["location"], json!("remote"));
        assert_eq!(flags(remote), (yes, no.clone(), no));
    }

    /// The kind is what the breakdown is read by, so a call site's own
    /// properties must not be able to rename it.
    #[test]
    fn a_call_site_cannot_rename_the_kind() {
        let props = error_properties("parse_failure", json!({ "kind": "map", "stage": "map" }));

        assert_eq!(props["kind"], json!("parse_failure"));
        assert_eq!(props["stage"], json!("map"));
    }

    /// The shape PostHog's Error Tracking parses (cymbal's `Exception` and
    /// `custom` frame); a wrong one is ingested as a plain event and makes no
    /// issue, silently.
    #[test]
    fn an_exception_is_shaped_for_error_tracking() {
        let props = exception_properties(
            "panic",
            "panic",
            "panic at src/session.rs:12",
            vec![frame("rust", "main", "src/session.rs", Some(12), Some(5))],
            json!({ "thread": "main" }),
        );

        let exception = &props["$exception_list"][0];
        assert_eq!(props["kind"], json!("panic"));
        assert_eq!(exception["type"], json!("panic"));
        assert_eq!(exception["stacktrace"]["type"], json!("raw"));
        let f = &exception["stacktrace"]["frames"][0];
        assert_eq!(f["platform"], json!("custom"));
        assert_eq!(f["function"], json!("main"));
        assert_eq!(f["lineno"], json!(12));
    }

    /// Webview frames arrive innermost first and leave outermost first, and a
    /// frame spelled with anything a path or message could carry is dropped.
    #[test]
    fn bundle_frames_keep_our_own_code_only() {
        let frames = bundle_frames(vec![
            "inner@index-a1.js:1:200".into(),
            "/Users/me/secret/project.js:1:2".into(),
            "outer@index-a1.js:3:40".into(),
        ]);

        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0]["function"], json!("outer"));
        assert_eq!(frames[0]["filename"], json!("index-a1.js"));
        assert_eq!(frames[0]["lineno"], json!(3));
        assert_eq!(frames[1]["colno"], json!(200));
    }

    #[test]
    fn crash_events_answer_to_the_crash_switch() {
        assert!(is_crash("$exception"));
        assert!(is_crash("error"));
        assert!(!is_crash("app_started"));
    }

    /// What the webview `$set`s as person properties, and the whole reason
    /// [`SurveyIdentity`] carries them: a survey targets *persons*, so these
    /// are the only fields a survey can be aimed with. `source` most of all —
    /// it is what tells an app person from a marketing-site one, and the site
    /// reports into the same project. Dropping one of these from
    /// [`base_properties`] costs a targeting option in PostHog's UI and says
    /// nothing at all here, which is what this pins.
    #[test]
    fn the_person_properties_carry_what_a_survey_is_targeted_by() {
        let props = base_properties();

        assert_eq!(props["source"], json!("app"));
        assert_eq!(props["app_version"], json!(env!("CARGO_PKG_VERSION")));
        assert!(props.contains_key("os"));
        assert!(props.contains_key("arch"));
    }

    /// What a panic report may carry. A dependency's path names the machine it
    /// was built on, and a local build's names this checkout — both are cut
    /// back to something that identifies the *code*, which is the whole of what
    /// the report is for.
    #[test]
    fn a_panic_location_names_code_and_not_a_machine() {
        assert_eq!(
            trim_source_path(
                "/Users/runner/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/tokio-1.47.1/src/task.rs"
            ),
            "index.crates.io-1949cf8c6b5b557f/tokio-1.47.1/src/task.rs"
        );
        assert_eq!(trim_source_path("src/session.rs"), "src/session.rs");
        assert_eq!(
            trim_source_path("/Users/morgan/Documents/ade/apps/desktop/src-tauri/src/lib.rs"),
            "lib.rs"
        );
    }

    /// The throttle itself: a day is claimed once, keys do not throttle each
    /// other, and the next day is a fresh claim. Distinct keys per test, since
    /// the state behind this is process-wide by design.
    #[test]
    fn a_key_reports_once_a_day() {
        assert!(claim_day("first".into(), "2026-09-13".into()));
        assert!(!claim_day("first".into(), "2026-09-13".into()));
        assert!(claim_day("second".into(), "2026-09-13".into()));
        assert!(claim_day("first".into(), "2026-09-14".into()));
    }

    /// The release workflow passes the host through from a repository variable,
    /// which expands to `""` rather than nothing when undefined — so the empty
    /// string has to read as unset. Taken literally it would post every event
    /// to `/i/v0/e/` with no host, and the failure is one line in a log nobody
    /// reads.
    #[test]
    fn an_empty_host_override_falls_back() {
        assert_eq!(host_of(Some("")), DEFAULT_HOST);
        assert_eq!(host_of(Some("https://eu.i.posthog.com")), "https://eu.i.posthog.com");
    }
}
