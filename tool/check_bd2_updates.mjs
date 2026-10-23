// Lists official BD2 notices that appeared since the last run.
// Usage: node tool/check_bd2_updates.mjs [--baseline]
// State (seen notice IDs) lives in .tool/bd2-watch-state.json, which git ignores.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const statePath = join(root, '.tool', 'bd2-watch-state.json');
const api = 'https://webapi.browndust2.com/api/notices';

let state = { seen: [] };
try {
  state = JSON.parse(readFileSync(statePath, 'utf8'));
} catch {}
const seen = new Set(state.seen);

const res = await fetch(`${api}?locale=zh-cn&page=0&limit=50`);
if (!res.ok) throw new Error(`Notices request failed: HTTP ${res.status}`);
const { items } = await res.json();
if (!Array.isArray(items) || items.length === 0) {
  throw new Error('Notices feed empty or malformed');
}

const fresh = process.argv.includes('--baseline')
  ? []
  : items.filter((item) => !seen.has(item.id));
for (const item of items) seen.add(item.id);

mkdirSync(dirname(statePath), { recursive: true });
writeFileSync(
  statePath,
  JSON.stringify({ checkedAt: new Date().toISOString(), seen: [...seen] }, null, 2),
);

console.log(
  JSON.stringify(
    fresh.map(({ id, subject, category, publishedAt }) => ({
      id,
      subject,
      category,
      publishedAt,
      detail: `${api}/${id}?locale=zh-cn`,
    })),
    null,
    2,
  ),
);
