import type { MetadataRoute } from "next";
import { SITE } from "@/lib/links";

/// Everything public may be crawled; the API and the signed-in account pages
/// are not worth it. Both sitemaps are named, since the docs are a separate build.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/api/", "/app/"] },
    sitemap: [`${SITE}/sitemap.xml`, `${SITE}/docs/sitemap.xml`],
  };
}
