import assert from "node:assert/strict";
import { test } from "node:test";

import { requestOrigin } from "../src/lib/origin.ts";

/// The origin a route redirects to, run on Node's own type stripping.

test("the proxy's host and scheme win over Next's own", () => {
  const req = new Request("https://localhost:3000/api/app/authorize?x=1", {
    headers: { "x-forwarded-host": "www.wainhq.com", "x-forwarded-proto": "https" },
  });
  assert.equal(requestOrigin(req), "https://www.wainhq.com");
});

test("behind two proxies, the first value is the client's", () => {
  const req = new Request("http://localhost:3000/api/link", {
    headers: { "x-forwarded-host": "wainhq.com, internal:3000", "x-forwarded-proto": "https,http" },
  });
  assert.equal(requestOrigin(req), "https://wainhq.com");
});

test("without a proxy, the request's own origin", () => {
  assert.equal(requestOrigin(new Request("http://localhost:3000/api/app/authorize")), "http://localhost:3000");
});
