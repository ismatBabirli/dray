/// The origin the client reached. Read off the proxy's headers first: Next's
/// standalone server rewrites `req.url`'s host to its own listen address, which
/// behind Coolify is https://localhost:3000. Without a proxy, as in dev,
/// `req.url` is right.
export function requestOrigin(req: Request): string {
  const url = new URL(req.url);
  const first = (name: string) => req.headers.get(name)?.split(",")[0]?.trim();
  const host = first("x-forwarded-host") || req.headers.get("host") || url.host;
  const proto = first("x-forwarded-proto") || url.protocol.slice(0, -1);
  return `${proto}://${host}`;
}
