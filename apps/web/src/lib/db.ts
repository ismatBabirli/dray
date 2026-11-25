import { Pool } from "pg";

const held = globalThis as { wainPool?: Pool };

/// The one Postgres pool per process. Held on `globalThis` because dev reloads
/// this module on every edit, and a pool per reload leaks connections to Railway.
export const pool = (held.wainPool ??= new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5,
}));
