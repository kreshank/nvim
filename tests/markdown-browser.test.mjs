// Run with MARKDOWN_BROWSER=/path/to/chrome node --test tests/markdown-browser.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
const require = createRequire(new URL('../lua/features/markdown/browser/package.json', import.meta.url));

async function until(callback) {
  for (let i = 0; i < 150; i++) {
    try { const value = await callback(); if (value) return value; } catch {}
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Timed out');
}

test('live browser rendering and Neovim navigation', { skip: !process.env.MARKDOWN_BROWSER }, async () => {
  const { chromium } = require('playwright');
  const root = await mkdtemp(path.join(tmpdir(), 'nvim-browser-'));
  const main = path.join(root, 'index.md');
  await mkdir(path.join(root, 'sub'));
  const other = path.join(root, 'sub/other page.md');
  await writeFile(main, String.raw`# First

[Go target](#target) [Go first](#first)
[Go other](sub/other%20page.md#destination)
[External](https://example.com)

Inline $x$ and \(y\).

$$z$$

\[w\]

![image](image.svg)

## Target

<details><summary>Details</summary>Hello</details>

<script>window.BAD = true</script>

` + '```mermaid\ngraph LR\n A-->B\n```');
  await writeFile(other, '# On disk\n\n## Destination');
  await writeFile(path.join(root, 'image.svg'), '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="red"/></svg>');
  const lua = `
vim.opt.hidden = true
local root = ${JSON.stringify(root)}
vim.ui.open = function(url)
  vim.fn.writefile({url}, root .. "/url")
  return {}
end
local other = vim.fn.bufadd(root .. "/sub/other page.md")
vim.fn.bufload(other)
vim.api.nvim_buf_set_lines(other, 0, -1, false, {"# Unsaved other", "", "## Destination"})
vim.cmd.edit(root .. "/index.md")
local main = vim.api.nvim_get_current_buf()
require("features.markdown.preview").start()
vim.wait(60000, function()
  vim.fn.writefile({vim.json.encode({path=vim.api.nvim_buf_get_name(0), line=vim.api.nvim_win_get_cursor(0)[1]})}, root .. "/position")
  if vim.fn.filereadable(root .. "/change") == 1 then
    vim.fn.delete(root .. "/change")
    vim.api.nvim_buf_set_lines(main, 0, 1, false, {"# Live unsaved"})
    vim.api.nvim_exec_autocmds("TextChanged", {buffer=main})
  end
  return vim.fn.filereadable(root .. "/done") == 1
end, 30)
require("features.markdown.preview").stop()
`;
  await writeFile(path.join(root, 'run.lua'), lua);
  const nvim = spawn('nvim', ['--headless', '-u', path.resolve('init.lua'), '-l', path.join(root, 'run.lua')]);
  let errors = '';
  nvim.stderr.on('data', chunk => { errors += chunk; });
  let browser, page;
  try {
    const url = (await until(async () => await readFile(path.join(root, 'url'), 'utf8'))).trim();
    browser = await chromium.launch({ executablePath: process.env.MARKDOWN_BROWSER, headless: true, args: ['--no-sandbox'] });
    page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    await page.goto(url);
    await page.waitForSelector('#user-content-target');
    await page.waitForSelector('.mermaid svg');
    assert.equal(await page.locator('.katex').count(), 4);
    assert.equal(await page.locator('.katex-display').count(), 2);
    assert.equal(await page.locator('main img').evaluate(img => img.complete && img.naturalWidth > 0), true);
    assert.equal(await page.evaluate(() => window.BAD), undefined);
    assert.equal(await page.getByText('External', { exact: true }).getAttribute('target'), '_blank');
    await page.getByText('Go target', { exact: true }).click();
    await until(async () => JSON.parse(await readFile(path.join(root, 'position'), 'utf8')).line === 15);
    assert.equal(new URL(page.url()).hash, '#target');
    await page.locator('#sync').uncheck();
    await page.getByText('Go first', { exact: true }).click();
    await page.waitForTimeout(150);
    assert.equal(JSON.parse(await readFile(path.join(root, 'position'), 'utf8')).line, 15);
    await page.locator('#sync').check();
    await writeFile(path.join(root, 'change'), 'yes');
    await page.getByRole('heading', { name: 'Live unsaved', exact: true }).waitFor();
    await page.getByText('Go other', { exact: true }).click();
    await page.getByRole('heading', { name: 'Unsaved other', exact: true }).waitFor();
    await until(async () => {
      const pos = JSON.parse(await readFile(path.join(root, 'position'), 'utf8'));
      return pos.path === other && pos.line === 3;
    });
    await page.goBack();
    await page.getByRole('heading', { name: 'Live unsaved', exact: true }).waitFor();
    await page.goForward();
    await page.getByRole('heading', { name: 'Unsaved other', exact: true }).waitFor();
    assert.deepEqual(pageErrors, []);
    await writeFile(path.join(root, 'done'), 'yes');
  } catch (error) {
    error.message += '\nNeovim output: ' + errors;
    if (page) error.message += '\nBrowser: ' + await page.locator('body').innerText();
    throw error;
  } finally {
    await browser?.close();
    nvim.kill();
    await rm(root, { recursive: true, force: true });
  }
});
