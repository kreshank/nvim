const article = document.getElementById('document');
const status = document.getElementById('status');
const sync = document.getElementById('sync');
let state = { version: 0 };
let rendering = false;
let mermaid;
let historyNavigation = false;

async function action(name, data) {
  const response = await fetch(name, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ version: state.version, ...data }),
  });
  if (response.status === 409) {
    const latest = await (await fetch('state')).json();
    if (latest.path === state.path && (name !== 'jump' || latest.source === state.source)) {
      // A cursor/navigation acknowledgement can change the revision without
      // changing the document. Preserve the rendered state until the next poll.
      const result = await fetch(name, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ version: latest.version, ...data }),
      });
      if (result.ok) return;
    }
  }
  if (!response.ok) throw new Error(response.status === 409
    ? 'Document changed; try the link again.' : await response.text());
}

function targetFor(fragment) {
  try {
    const name = 'user-content-' + decodeURIComponent(fragment);
    return document.getElementById(name) || document.getElementsByName(name)[0];
  }
  catch { return null; }
}
async function jump(fragment, push = true) {
  const target = targetFor(fragment);
  if (!target || !article.contains(target)) {
    status.textContent = `Section not found: #${fragment}`;
    return;
  }
  if (push) history.pushState({ path: state.path, fragment }, '', '#' + fragment);
  target.scrollIntoView({ block: 'start' });
  const line = Number(target.closest('[data-line]')?.dataset.line);
  if (line || state.fragment) await action('jump', { line: line || 1, sync: sync.checked && Boolean(line) });
}

function localLink(href) {
  return !/^(?:[a-z][\w+.-]*:|\/\/)/i.test(href);
}
function prepareLinks() {
  article.querySelectorAll('img').forEach(img => {
    const source = img.getAttribute('src');
    if (source && localLink(source)) {
      img.src = 'asset?path=' + encodeURIComponent(decodeURIComponent(source)) + '&from=' + encodeURIComponent(state.path);
    }
  });
  article.querySelectorAll('a[href]').forEach(link => {
    const href = link.getAttribute('href');
    if (/^(https?:|mailto:)/i.test(href)) {
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
    } else if (localLink(href) && /\.(pdf|png|jpe?g|gif|webp|svg)(?:[?#]|$)/i.test(href)) {
      link.href = 'asset?path=' + encodeURIComponent(decodeURIComponent(href.split('#')[0])) + '&from=' + encodeURIComponent(state.path);
      link.target = '_blank';
      link.rel = 'noopener';
      link.dataset.asset = 'true';
    }
  });
}

article.addEventListener('click', async event => {
  const link = event.target.closest('a[href]');
  if (!link || !article.contains(link) || link.dataset.asset) return;
  const href = link.getAttribute('href');
  if (!localLink(href)) return;
  // Relative document links must go through Neovim, including modified buffers.
  event.preventDefault();
  status.textContent = '';
  try {
    if (href.startsWith('#')) await jump(href.slice(1));
    else await action('navigate', { href });
  } catch (error) { status.textContent = error.message; }
});
window.addEventListener('popstate', async event => {
  if (!event.state) return;
  try {
    if (event.state.path === state.path) {
      if (event.state.fragment) await jump(event.state.fragment, false);
      else window.scrollTo(0, 0);
    } else {
      historyNavigation = true;
      await action('navigate', { href: event.state.path + '#' + (event.state.fragment || '') });
    }
  } catch (error) { status.textContent = error.message; }
});

async function refresh() {
  if (rendering) return;
  rendering = true;
  try {
    const response = await fetch('state?since=' + state.version);
    if (response.status === 204) return;
    if (!response.ok) throw new Error('Preview stopped. Use Space mp to restart.');
    const next = await response.json();
    const first = !state.path;
    const changed = next.path !== state.path || next.html !== state.html;
    const changedFile = next.path !== state.path;
    state = next;
    if (first) sync.checked = state.sync_navigation !== false;
    if (changed) {
      const position = window.scrollY;
      // Raw HTML is allowed in Markdown, but scripts/events/iframes are not.
      article.innerHTML = DOMPurify.sanitize(state.html, { ADD_TAGS: ['eq', 'eqn'], SANITIZE_NAMED_PROPS: true, FORBID_TAGS: ['style'] });
      prepareLinks();
      document.title = state.path.split('/').pop() + ' — Markdown';
      document.getElementById('filename').textContent = state.path;
      if (article.querySelector('.mermaid')) {
        mermaid ??= (await import('./vendor/mermaid/dist/mermaid.esm.min.mjs')).default;
        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'neutral' });
        try { await mermaid.run({ nodes: article.querySelectorAll('.mermaid') }); }
        catch { status.textContent = 'Invalid Mermaid diagram; check its source.'; }
      }
      window.scrollTo(0, changedFile ? 0 : position);
    }
    const fragment = state.fragment || (first ? location.hash.slice(1) : "");
    if (changedFile) {
      history[first || historyNavigation ? 'replaceState' : 'pushState'](
        { path: state.path, fragment }, '',
        location.pathname + (fragment ? '#' + fragment : '')
      );
    }
    if (fragment) await jump(fragment, !changedFile && !historyNavigation);
    historyNavigation = false;
  } catch (error) { status.textContent = error.message; }
  finally { rendering = false; }
}
async function poll() { await refresh(); setTimeout(poll, 250); }
poll();
