// Lists official BD2 notices that appeared since the last run.
// Usage: node tool/check_bd2_updates.mjs [--baseline] [--out <file>]
// --out also fetches each new notice's full text and writes the list as UTF-8 JSON.
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

const notices = fresh.map(({ id, subject, category, publishedAt }) => ({
  id,
  subject,
  category,
  publishedAt,
  detail: `${api}/${id}?locale=zh-cn`,
}));

const outIndex = process.argv.indexOf('--out');
if (outIndex !== -1) {
  for (const notice of notices) {
    const detail = await fetch(notice.detail);
    if (!detail.ok) throw new Error(`Notice ${notice.id}: HTTP ${detail.status}`);
    const { content = '' } = await detail.json();
    notice.content = content
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }
  writeFileSync(process.argv[outIndex + 1], JSON.stringify(notices, null, 2));
}

console.log(JSON.stringify(notices, null, 2));
