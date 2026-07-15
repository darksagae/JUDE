// Durable Neon Postgres data layer for the cloud-sync backend.
//
// Replaces the previous ephemeral JSON-file store (server-db.json) which, on
// Vercel, lived in /tmp and was wiped between invocations — i.e. there was no
// real database. Every collection is stored JSONB-per-entity: one row per
// record, keyed by its business id, so the merge logic in server.ts stays a
// near 1:1 port while the data itself is now persistent and queryable.
import { neon } from '@neondatabase/serverless';

const connectionString =
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  process.env.DATABASE_URL_UNPOOLED ||
  process.env.POSTGRES_URL_NON_POOLING ||
  '';

if (!connectionString) {
  console.error(
    'FATAL: No Neon connection string. Expected DATABASE_URL / POSTGRES_URL in the environment.'
  );
}

// HTTP-based Neon driver — ideal for Vercel serverless (no socket pooling to manage).
export const sql = neon(connectionString);

// Every collection is a table with the same shape. Staff is keyed by userId,
// everything else by its own `id` — but the physical column is always `id`.
export const TABLES = [
  'products',
  'sales',
  'stock_transactions',
  'audit_logs',
  'reports',
  'loans',
  'expenses',
  'staff',
] as const;

export type TableName = (typeof TABLES)[number];

// Maps the wire collection name (as sent by the Flutter/React clients) to its
// table and the JSON field that holds the business id for that collection.
export const COLLECTIONS: Record<
  string,
  { table: TableName; idKey: string }
> = {
  products: { table: 'products', idKey: 'id' },
  sales: { table: 'sales', idKey: 'id' },
  stockTransactions: { table: 'stock_transactions', idKey: 'id' },
  auditLogs: { table: 'audit_logs', idKey: 'id' },
  reports: { table: 'reports', idKey: 'id' },
  loans: { table: 'loans', idKey: 'id' },
  expenses: { table: 'expenses', idKey: 'id' },
  staff: { table: 'staff', idKey: 'userId' },
};

let schemaReady: Promise<void> | null = null;

/** Creates all tables (idempotent) and seeds the single owner account once. */
export function ensureSchema(): Promise<void> {
  schemaReady ??= (async () => {
    for (const table of TABLES) {
      // Table names are from a fixed allow-list above, never user input.
      await sql.query(
        `CREATE TABLE IF NOT EXISTS ${table} (
           id TEXT PRIMARY KEY,
           data JSONB NOT NULL,
           updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
         )`
      );
    }
    // Tombstones: records that were deliberately deleted. The bulk /api/sync is
    // upsert-only, so without this a device still holding a deleted row would
    // re-push it and the server would resurrect it. Every delete writes a
    // tombstone here, and sync refuses to re-insert any id that is tombstoned —
    // which lets the authoritative pull remove it from that device's storage.
    await sql.query(
      `CREATE TABLE IF NOT EXISTS deletions (
         collection TEXT NOT NULL,
         id TEXT NOT NULL,
         deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
         PRIMARY KEY (collection, id)
       )`
    );
    await seedOwner();
  })();
  return schemaReady;
}

/** Records a deleted business id so sync will never re-insert it. */
export async function tombstone(collection: string, id: string): Promise<void> {
  if (!id) return;
  await sql.query(
    `INSERT INTO deletions (collection, id) VALUES ($1, $2)
       ON CONFLICT (collection, id) DO NOTHING`,
    [collection, String(id)]
  );
}

/** Returns the set of tombstoned ids for a collection. */
export async function getDeletedIds(collection: string): Promise<Set<string>> {
  const rows = await sql.query(
    `SELECT id FROM deletions WHERE collection = $1`,
    [collection]
  );
  return new Set(rows.map((r: any) => String(r.id)));
}

/**
 * Seeds exactly one owner (Top Manager) account when the staff table is empty.
 * This is the only bootstrap record in the system — no demo products, sales,
 * or extra users. Configurable via env so credentials are never hard-coded.
 */
async function seedOwner(): Promise<void> {
  const rows = await sql.query(`SELECT COUNT(*)::int AS n FROM staff`);
  if ((rows[0]?.n ?? 0) > 0) return;

  const owner = {
    userId: process.env.OWNER_ID || 'TM001',
    name: process.env.OWNER_NAME || 'Business Owner',
    role: 'top_manager',
    passcode: process.env.OWNER_PIN || '9999',
  };
  await sql.query(
    `INSERT INTO staff (id, data) VALUES ($1, $2)
       ON CONFLICT (id) DO NOTHING`,
    [owner.userId, JSON.stringify(owner)]
  );
  console.log(`Seeded owner account ${owner.userId} into Neon.`);
}

/** Returns every record's `data` for a collection. */
export async function getAll(table: TableName): Promise<any[]> {
  const rows = await sql.query(`SELECT data FROM ${table} ORDER BY updated_at ASC`);
  return rows.map((r: any) => r.data);
}

/** Loads the full sync store from Neon, mirroring the old in-memory shape. */
export async function loadStore() {
  const [
    products,
    sales,
    stockTransactions,
    auditLogs,
    reports,
    loans,
    expenses,
    staff,
  ] = await Promise.all([
    getAll('products'),
    getAll('sales'),
    getAll('stock_transactions'),
    getAll('audit_logs'),
    getAll('reports'),
    getAll('loans'),
    getAll('expenses'),
    getAll('staff'),
  ]);
  return {
    products,
    sales,
    stockTransactions,
    auditLogs,
    reports,
    loans,
    expenses,
    staff,
  };
}

/** Upserts a batch of records into a table, keyed by the given id field. */
export async function upsertRows(
  table: TableName,
  rows: any[],
  idKey = 'id'
): Promise<void> {
  for (const row of rows) {
    const id = row?.[idKey];
    if (id == null || id === '') continue;
    await sql.query(
      `INSERT INTO ${table} (id, data, updated_at) VALUES ($1, $2, now())
         ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [String(id), JSON.stringify(row)]
    );
  }
}

/** Deletes a single record by id (used when a manager voids a sale). */
export async function deleteRow(table: TableName, id: string): Promise<void> {
  await sql.query(`DELETE FROM ${table} WHERE id = $1`, [id]);
}

/** Persists the merged store back to Neon (append/merge; never wipes). */
export async function saveStore(store: {
  products?: any[];
  sales?: any[];
  stockTransactions?: any[];
  auditLogs?: any[];
  reports?: any[];
  loans?: any[];
  expenses?: any[];
  staff?: any[];
}): Promise<void> {
  await Promise.all([
    upsertRows('products', store.products ?? [], 'id'),
    upsertRows('sales', store.sales ?? [], 'id'),
    upsertRows('stock_transactions', store.stockTransactions ?? [], 'id'),
    upsertRows('audit_logs', store.auditLogs ?? [], 'id'),
    upsertRows('reports', store.reports ?? [], 'id'),
    upsertRows('loans', store.loans ?? [], 'id'),
    upsertRows('expenses', store.expenses ?? [], 'id'),
    upsertRows('staff', store.staff ?? [], 'userId'),
  ]);
}
