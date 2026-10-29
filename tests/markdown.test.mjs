import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { render } from '../lua/features/markdown/browser/render.mjs';

export async function fixture() {
  const root = await mkdtemp(path.join(tmpdir(), 'nvim-markdown-'));
  const document = path.join(root, 'index.md');
  await writeFile(document, '# Document');
  await writeFile(path.join(root, 'other page.md'), '# Other\n\n## Section');
  await writeFile(path.join(root, 'image.svg'), '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>');
  const process = spawn('node', [new URL('../lua/features/markdown/browser/server.mjs', import.meta.url).pathname]);
  const messages = [];
  const reader = createInterface({ input: process.stdout });
  const ready = new Promise(resolve => reader.on('line', line => {
    const data = JSON.parse(line);
    messages.push(data);
    if (data.event === 'ready') resolve(data.url);
  }));
  const url = await ready;
  let source = '';
  async function update(text, extra = {}) {
    source = text;
    process.stdin.write(JSON.stringify({ path: document, root, source, sync_navigation: true, ...extra }) + '\n');
    for (let i = 0; i < 100; i++) {
      const state = await (await fetch(url + 'state')).json();
      if (state.source === source && state.path === (extra.path || document)) return state;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error('Update timed out');
  }
  return { root, document, process, url, update, messages,
    async close() { process.kill(); reader.close(); await rm(root, { recursive: true, force: true }); } };
}

test('all math delimiters, multiline blocks, and code exclusion', () => {
  const html = render(String.raw`Inline $a$ and \(b\).

$$
c+d
$$

\[
e+f
\]

` + '`$not_math$`\n\n```tex\n\\(not_math\\)\n```');
  assert.equal((html.match(/class="katex"/g) || []).length, 4);
  assert.match(html, /<code>\$not_math\$<\/code>/);
  assert.equal((html.match(/class="katex-display"/g) || []).length, 2);
});

test('anchors use source lines, duplicate and Unicode headings; fences are ignored', () => {
  const html = render('# Hello, **world**!\n\n# Hello, **world**!\n\nCafé\n----\n\n## Custom {#my-anchor}\n\n```md\n# fake\n```');
  assert.match(html, /data-line="1" id="hello-world"/);
  assert.match(html, /data-line="3" id="hello-world-1"/);
  assert.match(html, /data-line="5" id="café"/);
  assert.match(html, /id="my-anchor"/);
  assert.doesNotMatch(html, /id="fake"/);
});

test('common Markdown constructs and reference links', () => {
  const html = render('[Read][section]\n\n[section]: #heading\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n- [x] complete\n\n~~old~~ :smile:\n\nNote[^1]\n\n[^1]: footnote\n\nTerm\n: Definition\n\n<details><summary>More</summary>Content</details>');
  for (const expected of ['href="#heading"', '<table', 'task-list-item-checkbox', '<s>old</s>', 'footnote', '<dl', '<details>']) {
    assert.ok(html.includes(expected), expected);
  }
});

test('HTTP navigation, local images, and boundary validation', async () => {
  const f = await fixture();
  try {
    const state = await f.update('# Start\n\n## Target');
    const post = (route, value, origin = new URL(f.url).origin) => fetch(f.url + route, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Origin: origin },
      body: JSON.stringify({ version: state.version, ...value }),
    });
    assert.equal((await post('jump', { line: 3 })).status, 204);
    assert.equal((await post('navigate', { href: 'other%20page.md#section' })).status, 204);
    assert.equal((await post('jump', { line: 999 })).status, 400);
    assert.equal((await post('jump', { line: 1 }, 'https://example.com')).status, 400);
    assert.equal((await post('navigate', { href: '../outside.md' })).status, 400);
    assert.equal((await fetch(f.url + 'asset?path=image.svg')).status, 200);
    assert.equal((await fetch(f.url + 'asset?path=index.md')).status, 400);
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.ok(f.messages.some(m => m.event === 'jump' && m.line === 3));
    assert.ok(f.messages.some(m => m.event === 'navigate' && m.path.endsWith('other page.md') && m.fragment === 'section'));
  } finally { await f.close(); }
});
