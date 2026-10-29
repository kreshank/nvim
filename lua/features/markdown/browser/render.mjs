import MarkdownIt from 'markdown-it';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import deflist from 'markdown-it-deflist';
import { full as emoji } from 'markdown-it-emoji';
import GithubSlugger from 'github-slugger';
import hljs from 'highlight.js';

const md = new MarkdownIt({
  html: true, linkify: true, typographer: false,
  highlight(code, language) {
    return language && hljs.getLanguage(language)
      ? hljs.highlight(code, { language, ignoreIllegals: true }).value : '';
  },
}).use(texmath, {
  engine: katex, delimiters: ['dollars', 'brackets'],
  katexOptions: { throwOnError: false, trust: false, strict: 'ignore' },
}).use(footnote).use(taskLists).use(deflist).use(emoji);

// Token maps are source lines, so headings inside fences never become anchors.
md.core.ruler.push('source_locations', state => {
  const slugger = new GithubSlugger();
  for (let i = 0; i < state.tokens.length; i++) {
    const token = state.tokens[i];
    if (token.map && (token.nesting === 1 || token.type === 'fence')) {
      token.attrSet('data-line', String(token.map[0] + 1));
    }
    if (token.type === 'heading_open') {
      const inline = state.tokens[i + 1];
      let explicit;
      const match = inline.content.match(/\s+\{#([\w-]+)\}\s*$/);
      if (match) {
        explicit = match[1];
        inline.content = inline.content.slice(0, match.index);
        inline.children = md.parseInline(inline.content, state.env)[0].children;
      }
      const text = inline.children.map(child =>
        ['text', 'code_inline', 'emoji', 'math_inline'].includes(child.type) ? child.content : ''
      ).join('');
      token.attrSet('id', explicit || slugger.slug(text));
    }
  }
});
const fence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, index, options, env, renderer) => {
  const token = tokens[index];
  const line = token.map[0] + 1;
  if (token.info.trim() === 'mermaid') {
    return `<pre class="mermaid" data-line="${line}">${md.utils.escapeHtml(token.content)}</pre>`;
  }
  return `<div data-line="${line}">${fence(tokens, index, options, env, renderer)}</div>`;
};

export function render(source) {
  // Preserve line numbering while hiding YAML front matter.
  source = source.replace(/^---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/,
    match => match.replace(/[^\n]/g, ''));
  return md.render(source);
}
