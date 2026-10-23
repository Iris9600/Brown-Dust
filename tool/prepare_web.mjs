// Run after flutter build web --no-web-resources-cdn.
import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'build/web');
async function files(directory, prefix = '') {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const name = prefix + entry.name;
    if (entry.isDirectory()) result.push(...await files(path.join(directory, entry.name), name + '/'));
    else if (!name.endsWith('.map') && !['sw.js', 'flutter_service_worker.js'].includes(name)) result.push(name);
  }
  return result.sort();
}
const assets = await files(root);
const hash = createHash('sha256');
for (const name of assets) hash.update(name).update(await readFile(path.join(root, name)));
const version = hash.digest('hex').slice(0, 16);
await writeFile(path.join(root, 'sw.js'), `
const CACHE = 'bd2-mobile-${version}';
const ASSETS = ${JSON.stringify(assets)};
const local = (name) => new URL(name, self.registration.scope).href;
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS.map(local))));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(key => key.startsWith('bd2-mobile-') && key !== CACHE).map(key => caches.delete(key))
  )).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || !event.request.url.startsWith(self.registration.scope)) return;
  event.respondWith(caches.open(CACHE).then(async cache => {
    if (event.request.mode === 'navigate') return (await cache.match(local('index.html'))) || fetch(event.request);
    return (await cache.match(event.request)) || fetch(event.request);
  }));
});
`);
console.log(`Prepared offline web app: ${assets.length} files, version ${version}`);
