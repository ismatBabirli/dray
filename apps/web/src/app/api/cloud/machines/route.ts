import { machines, route, startMachine } from "@/lib/cloud/cloud";
import { requestOrigin } from "@/lib/origin";

export const runtime = "nodejs";
// Without it a GET that answers 404 before touching the request is prerendered
// at build, and stays a 404 after `WAIN_CLOUD_KEY` is set.
export const dynamic = "force-dynamic";

export const GET = route("client", async (_req, { serveToken }) => Response.json(await machines(serveToken)));

export const POST = route("client", async (req, secrets) => startMachine(requestOrigin(req), secrets));
