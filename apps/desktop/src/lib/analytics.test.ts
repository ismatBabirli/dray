import { describe, expect, it } from "vitest";

import { bundleFrames } from "./analytics";

describe("bundleFrames", () => {
  it("reads WebKit frames and drops anything outside the bundle", () => {
    const stack = [
      "renderRow@tauri://localhost/assets/index-a1b2.js:12:340",
      "global code@tauri://localhost/assets/index-a1b2.js:1:9",
      "readFile@file:///Users/me/secret/project/x.js:3:4",
    ].join("\n");

    expect(bundleFrames(stack)).toEqual(["renderRow@index-a1b2.js:12:340", "global_code@index-a1b2.js:1:9"]);
  });

  it("reads Chromium frames, named and anonymous", () => {
    const stack = [
      "TypeError: cannot read /Users/me/private",
      "    at onClick (http://tauri.localhost/assets/index-a1b2.js:5:6)",
      "    at http://tauri.localhost/assets/vendor-9.js:7:8",
    ].join("\n");

    expect(bundleFrames(stack)).toEqual(["onClick@index-a1b2.js:5:6", "anonymous@vendor-9.js:7:8"]);
  });
});
