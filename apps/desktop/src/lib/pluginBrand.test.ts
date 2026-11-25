import { describe, expect, it } from "vitest";

import { commandBrand } from "./pluginBrand";

describe("commandBrand", () => {
  // Wain holds no vendor's colour (pluginBrand.ts), Greptile's included.
  it("tints no plugin's command", () => {
    expect(commandBrand("/greptile:review")).toBeNull();
    expect(commandBrand("/greploop")).toBeNull();
    expect(commandBrand("/check-pr 173")).toBeNull();
  });

  it("leaves every other message alone", () => {
    expect(commandBrand("/review")).toBeNull();
    expect(commandBrand("/railway:deploy")).toBeNull();
    expect(commandBrand("run /greptile:review for me")).toBeNull();
    expect(commandBrand("")).toBeNull();
  });

  // A lookup without hasOwn would find Object.prototype's own names.
  it("never hands back a prototype member as a colour", () => {
    expect(commandBrand("/valueOf")).toBeNull();
    expect(commandBrand("/constructor")).toBeNull();
  });
});
