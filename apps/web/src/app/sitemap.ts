import type { MetadataRoute } from "next";
import { SITE } from "@/lib/links";

/// The pages worth a search result. Sign-in, linking, the account and org
/// pages and /thank-you (noindex) are left out; the docs keep a sitemap of their
/// own at /docs/sitemap.xml, which robots.txt names beside this one.
export default function sitemap(): MetadataRoute.Sitemap {
  return ["", "/download", "/changelog", "/faq", "/help"].map((path) => ({ url: `${SITE}${path}` }));
}
