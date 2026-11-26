// Retakes the docs' server-setup screenshots (apps/docs/content/images/server-*.png)
// from the desktop's server-setup demo, each in both themes, cropped to its dialog at 2x.
// Run it again after a change to these dialogs:
//
//   cd apps/desktop && pnpm exec vite --port 1477 --strictPort &
//   node scripts/docs-screenshots.mjs http://localhost:1477 apps/docs/content/images
//
// Borrows apps/brand-video's playwright-core; CHROMIUM_PATH picks the browser, as there.
import { createRequire } from "node:module";
const require = createRequire(new URL("../apps/brand-video/package.json", import.meta.url));
const { chromium } = require("playwright-core");

const [base, out] = process.argv.slice(2);
// [file, scene button, text the dialog shows once the scene has settled, a row to pick]
const SHOTS = [
  ["server-add", "SSH line typed", "Add server"],
  ["server-install", "Wain missing: the pick-list", "Also install"],
  ["server-sign-in", "Logins on the server", "Sign in on vps"],
  ["server-attach", "Repos on the server", "Attach project", "octocat/storefront"],
];

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage({ viewport: { width: 1280, height: 1000 }, deviceScaleFactor: 2 });
// Wain's own palette: the demo otherwise keeps whichever one it last showed.
await page.addInitScript(() => localStorage.setItem("ade.theme", "default"));
for (const [name, scene, settled, pick] of SHOTS) {
  for (const theme of ["dark", "light"]) {
    await page.goto(`${base}/demo/server-setup.html`, { waitUntil: "networkidle" });
    // Opaque surfaces, as on Linux: the Mac's glass shows the page through headless Chromium.
    await page.evaluate(() => document.documentElement.removeAttribute("data-transparency"));
    await page.getByRole("button", { name: theme === "dark" ? "Dark" : "Light", exact: true }).first().click();
    await page.getByRole("button", { name: scene, exact: true }).click();
    const dialog = page.locator('[role="dialog"]', { hasText: settled }).last();
    await dialog.waitFor({ state: "visible", timeout: 30000 });
    if (pick) await dialog.getByText(pick, { exact: true }).click();
    await page.waitForTimeout(1500);
    const file = `${out}/${name}${theme === "light" ? "-light" : ""}.png`;
    await dialog.screenshot({ path: file, animations: "disabled" });
    console.log("wrote", file);
  }
}
await browser.close();
