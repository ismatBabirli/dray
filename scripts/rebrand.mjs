#!/usr/bin/env node
/// Renames a checkout of upstream Dray to Wain, in place: file contents, paths
/// and symlink targets. Deterministic, so upstream syncs merge cleanly (FORK-PLAN.md §1).
///
///   node scripts/rebrand.mjs <git checkout>   rename that tree
///   node scripts/rebrand.mjs --self-test      check the rules
///
/// Lives on our branch only, never in the tree it renames.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

// Order matters: the specific rules run before the generic one eats their "dray".
// Every rule keeps the length but the two monorepo-labs ones, so byte offsets in
// fixtures mostly survive.
// The owner is lowercase because the code lowercases GitHub owners before comparing
// (git.rs, pr.ts); a camel-case one fails its own tests.
const RULES = [
  [/monorepo-labs\.github\.io\/dray/g, "ismatbabirli.github.io/wain"],
  [/monorepo-labs/g, "ismatbabirli"],
  [/Monorepo-Labs/g, "IsmatBabirli"],
  [/com([./])yogesh\1dray/g, "com$1wainhq$1dray"],
  // server_id's pinned vector in Rust, Swift and Kotlin: sha256 of "dray-server\0test-token"
  // becomes the "wain-server\0" one, or all three tests fail on the renamed salt.
  [/4b3f3d0f73afd9cc/g, "350581a0ddbc1421"],
  [/DRAY/g, "WAIN"],
  [/Dray/g, "Wain"],
  [/dray/g, "wain"],
];
// Copied verbatim: the license names the upstream copyright holder.
const UNTOUCHED = new Set(["LICENSE"]);

export const rebrand = (s) => RULES.reduce((acc, [re, to]) => acc.replace(re, to), s);

// Files their generators keep sorted by name. A rename moves dray-proto to wain-proto
// and DrayUser to WainUser without moving them, the next build re-sorts, and a re-sorted
// copy on wain would conflict with every later sync. So they are re-sorted here, the way
// the generator does it; run() first checks each sorter leaves upstream's own file as it is.
const byteCmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/// Semver order: numeric core, a release after its pre-releases (cargo sorts versions this way).
function versionCmp(a = "", b = "") {
  const parse = (v) => {
    const [core, pre] = v.split("+")[0].split(/-(.+)/);
    return [core.split(".").map(Number), pre];
  };
  const [ca, pa] = parse(a);
  const [cb, pb] = parse(b);
  for (let i = 0; i < 3; i++) if ((ca[i] || 0) !== (cb[i] || 0)) return (ca[i] || 0) - (cb[i] || 0);
  if (pa === pb) return 0;
  if (pa === undefined) return 1;
  if (pb === undefined) return -1;
  const xa = pa.split(".");
  const xb = pb.split(".");
  for (let i = 0; i < Math.max(xa.length, xb.length); i++) {
    if (xa[i] === undefined) return -1;
    if (xb[i] === undefined) return 1;
    const na = /^\d+$/.test(xa[i]);
    const nb = /^\d+$/.test(xb[i]);
    if (na && nb && +xa[i] !== +xb[i]) return +xa[i] - +xb[i];
    if (na !== nb) return na ? -1 : 1;
    if (xa[i] !== xb[i]) return byteCmp(xa[i], xb[i]);
  }
  return 0;
}

/// Cargo's order: packages, and each package's dependency list, by name, version, source.
function sortCargoLock(text) {
  const idCmp = (a, b) => byteCmp(a.name, b.name) || versionCmp(a.version, b.version) || byteCmp(a.source || "", b.source || "");
  const dep = (line) => {
    const [name, version, source] = line.trim().replace(/^"|",?$/g, "").split(" ");
    return { line, name, version, source };
  };
  const field = (block, key) => (block.match(new RegExp(`^${key} = "([^"]*)"`, "m")) || [])[1];
  const [head, ...blocks] = text.split(/\n(?=\[\[package\]\]\n)/);
  const pkgs = blocks.map((b) => {
    const sorted = b.replace(/^(dependencies = \[\n)([\s\S]*?\n)(\])/m, (_, open, body, close) =>
      open + body.split("\n").filter(Boolean).map(dep).sort(idCmp).map((d) => d.line + "\n").join("") + close);
    return { block: sorted, name: field(b, "name"), version: field(b, "version"), source: field(b, "source") };
  });
  return [head, ...pkgs.sort(idCmp).map((p) => p.block)].join("\n");
}

/// ts-rs writes every type into one file, one blank-line-separated block each, by name.
function sortTsRs(text) {
  const [head, ...blocks] = text.replace(/\n$/, "").split("\n\n");
  const name = (b) => (b.match(/^export type (\w+)/m) || [])[1];
  if (!blocks.length || blocks.some((b) => !name(b))) return text;
  return [head, ...blocks.sort((a, b) => byteCmp(name(a), name(b)))].join("\n\n") + "\n";
}

const SORTERS = [
  [/(^|\/)Cargo\.lock$/, sortCargoLock],
  [/^apps\/desktop\/src\/types\/events\.ts$/, sortTsRs],
];
const sorterFor = (file) => (SORTERS.find(([re]) => re.test(file)) || [])[1];

function selfTest() {
  const cases = [
    ["Dray / dray / DRAY_HOME", "Wain / wain / WAIN_HOME"],
    ["useDrayAccount DrayError dray_account.rs", "useWainAccount WainError wain_account.rs"],
    ["https://www.drayhq.com/install.sh", "https://www.wainhq.com/install.sh"],
    ["https://monorepo-labs.github.io/dray/stable.json", "https://ismatbabirli.github.io/wain/stable.json"],
    ["gh issue create --repo monorepo-labs/dray", "gh issue create --repo ismatbabirli/wain"],
    ['owner: "monorepo-labs", repo: "dray"', 'owner: "ismatbabirli", repo: "wain"'],
    ["com.yogesh.dray.server", "com.wainhq.wain.server"],
    ["app/src/main/java/com/yogesh/dray/wire/Wire.kt", "app/src/main/java/com/wainhq/wain/wire/Wire.kt"],
    // His own MIT package, a real dependency: must survive.
    ["@yogesharc/thinking-orbs com.github.yogesharc:thinking-orbs", "@yogesharc/thinking-orbs com.github.yogesharc:thinking-orbs"],
    ["Copyright 2026 Yogesh Dhakal", "Copyright 2026 Yogesh Dhakal"],
    ["https://github.com/Monorepo-Labs/dray/pull/1", "https://github.com/IsmatBabirli/wain/pull/1"],
  ];
  for (const [from, to] of cases) assert.equal(rebrand(from), to);

  const lock = [
    "# generated\nversion = 4\n",
    '[[package]]\nname = "dray"\nversion = "0.1.0"\ndependencies = [\n "dray-proto",\n "serde",\n "windows-sys 0.10.0",\n "windows-sys 0.9.0",\n]\n',
    '[[package]]\nname = "dray-proto"\nversion = "0.1.0"\n',
    '[[package]]\nname = "serde"\nversion = "1.0.0"\n',
  ].join("\n");
  const sorted = sortCargoLock(rebrand(lock));
  assert.deepEqual([...sorted.matchAll(/^name = "(.+)"/gm)].map((m) => m[1]), ["serde", "wain", "wain-proto"]);
  assert.match(sorted, /\[\n "serde",\n "wain-proto",\n "windows-sys 0.9.0",\n "windows-sys 0.10.0",\n\]/);
  assert.equal(sortCargoLock(sorted), sorted);

  const ts = "// header\n\nexport type Access = 1;\n\nexport type DrayUser = 2;\n\nexport type Model = 3;\n";
  assert.equal(sortTsRs(rebrand(ts)), "// header\n\nexport type Access = 1;\n\nexport type Model = 3;\n\nexport type WainUser = 2;\n");
  console.log(`self-test: ${cases.length} rename cases and both sorters pass`);
}

/// A file is text when its first 8 KB hold no NUL and it round-trips as UTF-8, git's own test plus one.
function textOf(buf) {
  if (buf.subarray(0, 8000).includes(0)) return null;
  const s = buf.toString("utf8");
  return Buffer.from(s, "utf8").equals(buf) ? s : null;
}

function run(root) {
  root = path.resolve(root);
  const listing = execFileSync("git", ["-C", root, "ls-files", "-s", "-z"], { maxBuffer: 1 << 28 })
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .map((line) => {
      const [meta, file] = line.split("\t");
      return { mode: meta.split(" ")[0], file };
    })
    .sort((a, b) => (a.file < b.file ? -1 : 1));

  let edited = 0;
  let moved = 0;
  const leftovers = [];
  const base64Hits = [];
  const unsortable = [];

  for (const { mode, file } of listing) {
    if (UNTOUCHED.has(file)) continue;
    const abs = path.join(root, file);
    if (mode === "120000") {
      const target = fs.readlinkSync(abs);
      const next = rebrand(target);
      if (next !== target) {
        fs.unlinkSync(abs);
        fs.symlinkSync(next, abs);
        edited++;
      }
    } else {
      const text = textOf(fs.readFileSync(abs));
      if (text !== null) {
        // A brand word inside a long base64 run is probably data, not a name: flag it for a human.
        for (const m of text.matchAll(/[A-Za-z0-9+/=]{64,}/g)) if (/dray/i.test(m[0])) base64Hits.push(file);
        let next = rebrand(text);
        const sort = sorterFor(rebrand(file));
        if (sort) {
          if (sort(text) === text) next = sort(next);
          else unsortable.push(file);
        }
        if (next !== text) {
          fs.writeFileSync(abs, next);
          edited++;
        }
        if (/dray/i.test(next)) leftovers.push(file);
      }
    }
    const renamed = rebrand(file);
    if (renamed !== file) {
      fs.mkdirSync(path.dirname(path.join(root, renamed)), { recursive: true });
      fs.renameSync(abs, path.join(root, renamed));
      moved++;
    }
  }

  // Directories emptied by the moves: git tracks none, so leaving them only clutters a checkout.
  const prune = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true }))
      if (e.isDirectory() && e.name !== ".git") prune(path.join(dir, e.name));
    if (dir !== root && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
  };
  prune(root);

  console.log(`rebrand: ${listing.length} files, ${edited} edited, ${moved} renamed`);
  if (leftovers.length) console.log(`WARN still says dray (another casing?): ${[...new Set(leftovers)].join(", ")}`);
  if (base64Hits.length) console.log(`WARN dray inside base64-like data, check by hand: ${[...new Set(base64Hits)].join(", ")}`);
  if (unsortable.length) console.log(`WARN sorter disagrees with upstream's own file, left unsorted: ${unsortable.join(", ")}`);
  return leftovers.length || base64Hits.length || unsortable.length ? 1 : 0;
}

const arg = process.argv[2];
if (arg === "--self-test") selfTest();
else if (arg && !arg.startsWith("-")) process.exit(run(arg));
else {
  console.error("usage: node scripts/rebrand.mjs <git checkout> | --self-test");
  process.exit(2);
}
