import http from 'node:http';
import { createInterface } from 'node:readline';
import { randomBytes } from 'node:crypto';
import { readFile, realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { render } from './render.mjs';

const directory = path.dirname(fileURLToPath(import.meta.url));
const token = randomBytes(24).toString('hex');
const prefix = `/${token}/`;
let state = { version: 0 };
let origin;
const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
const within = (root, name) => name === root || name.startsWith(root + path.sep);

async function projectFile(name) {
  const root = await realpath(state.root);
  const resolved = await realpath(name);
  if (!within(root, resolved)) throw new Error('Link is outside the preview project');
  if (!(await stat(resolved)).isFile()) throw new Error('Link is not a file');
  return resolved;
}

const types = {
  '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.html': 'text/html', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
  '.avif': 'image/avif', '.ico': 'image/x-icon', '.pdf': 'application/pdf',
};
async function sendFile(response, file) {
  const content = await readFile(file);
  response.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  response.end(content);
}

const server = http.createServer(async (request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  try {
    if (request.headers.host !== new URL(origin).host) throw new Error('Invalid host');
    const url = new URL(request.url, origin);
    if (!url.pathname.startsWith(prefix)) { response.writeHead(404).end(); return; }
    const route = url.pathname.slice(prefix.length);
    if (request.method === 'POST') {
      if (request.headers.origin !== origin || request.headers['content-type'] !== 'application/json') {
        throw new Error('Invalid navigation request');
      }
      let body = '';
      for await (const chunk of request) {
        body += chunk;
        if (body.length > 16384) throw new Error('Request too large');
      }
      const data = JSON.parse(body);
      if (data.version !== state.version) { response.writeHead(409).end(); return; }
      if (route === 'jump') {
        if (!Number.isInteger(data.line) || data.line < 1 || data.line > state.lines) {
          throw new Error('Invalid source line');
        }
        emit({ event: 'jump', path: state.path, line: data.line, sync: data.sync !== false });
      } else if (route === 'navigate') {
        // href is decoded as a URL path, not interpreted as a shell/Vim command.
        const href = new URL(data.href, 'http://document/' + state.path.replace(/^\//, ''));
        if (href.origin !== 'http://document') throw new Error('Not a local document link');
        const target = await projectFile(decodeURIComponent(href.pathname));
        if (!/\.(md|markdown)$/i.test(target)) throw new Error('Link is not a Markdown document');
        emit({ event: 'navigate', path: target, fragment: href.hash.slice(1) });
      } else throw new Error('Unknown action');
      response.writeHead(204).end();
      return;
    }
    if (request.method !== 'GET') { response.writeHead(405).end(); return; }
    if (route === 'state') {
      if (Number(url.searchParams.get('since')) === state.version) response.writeHead(204).end();
      else {
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify(state));
      }
    } else if (route === 'asset') {
      const relative = url.searchParams.get('path');
      const target = await projectFile(path.resolve(path.dirname(url.searchParams.get('from') || state.path), relative));
      if (!['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.avif', '.ico', '.pdf'].includes(path.extname(target).toLowerCase())) {
        throw new Error('Unsupported local asset');
      }
      await sendFile(response, target);
    } else if (route.startsWith('vendor/')) {
      const relative = route.slice(7);
      if (!['katex/dist/', 'dompurify/dist/', 'highlight.js/styles/', 'mermaid/dist/'].some(p => relative.startsWith(p))) {
        throw new Error('Unknown asset');
      }
      const root = path.join(directory, 'node_modules');
      const target = await realpath(path.join(root, relative));
      if (!within(root, target)) throw new Error('Invalid asset');
      await sendFile(response, target);
    } else if (['', 'client.js', 'style.css'].includes(route)) {
      await sendFile(response, path.join(directory, route || 'index.html'));
    } else response.writeHead(404).end();
  } catch (error) {
    response.writeHead(400, { 'Content-Type': 'text/plain' });
    response.end(error.message);
  }
});

createInterface({ input: process.stdin }).on('line', line => {
  try {
    const update = JSON.parse(line);
    const changed = update.source !== state.source || update.path !== state.path;
    state = { ...update, version: state.version + 1,
      lines: update.source.split('\n').length,
      html: changed ? render(update.source) : state.html };
  } catch (error) { emit({ event: 'error', message: error.message }); }
}).on('close', () => server.close(() => process.exit(0)));
server.listen(0, '127.0.0.1', () => {
  origin = `http://127.0.0.1:${server.address().port}`;
  emit({ event: 'ready', url: origin + prefix });
});
