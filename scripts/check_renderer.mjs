import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const scriptsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(scriptsDirectory);
const rendererRoot = path.join(
  repositoryRoot,
  "Sources",
  "Glosslet",
  "Resources",
  "MarkdownRenderer"
);
const vendorRoot = path.join(rendererRoot, "vendor");
const require = createRequire(import.meta.url);

const requiredFiles = [
  "index.html",
  "renderer.js",
  "style.css",
  "vendor/markdown-it.min.js",
  "vendor/highlight.min.js",
  "vendor/katex.min.js",
  "vendor/katex.min.css",
  "vendor/auto-render.min.js",
  "vendor/LICENSE.markdown-it",
  "vendor/LICENSE.katex",
  "vendor/LICENSE.highlightjs",
];

for (const relativePath of requiredFiles) {
  const absolutePath = path.join(rendererRoot, relativePath);
  assert.ok(fs.statSync(absolutePath).size > 0, `${relativePath} is empty`);
}

const fontFiles = fs
  .readdirSync(path.join(vendorRoot, "fonts"))
  .filter((name) => name.endsWith(".woff2"));
assert.ok(fontFiles.length >= 20, "KaTeX font bundle is incomplete");

const indexHTML = fs.readFileSync(
  path.join(rendererRoot, "index.html"),
  "utf8"
);
assert.ok(
  indexHTML.includes("connect-src 'none'"),
  "renderer must block runtime connections"
);
assert.ok(
  !/https?:\/\//i.test(indexHTML),
  "renderer HTML must not use remote assets"
);

const MarkdownIt = require(path.join(vendorRoot, "markdown-it.min.js"));
const markdown = MarkdownIt({
  html: false,
  linkify: true,
});
const rendered = markdown.render(`
| Feature | State |
| --- | --- |
| Table | Ready |

\`\`\`swift
let answer = 42
\`\`\`

<script>unsafe()</script>
`);
assert.ok(rendered.includes("<table>"), "table rendering failed");
assert.ok(
  rendered.includes('class="language-swift"'),
  "fenced-code rendering failed"
);
assert.ok(
  rendered.includes("&lt;script&gt;"),
  "raw HTML must remain escaped"
);

const katex = require(path.join(vendorRoot, "katex.min.js"));
const formula = katex.renderToString(
  String.raw`\frac{e^{x_i}}{\sum_j e^{x_j}}`,
  { throwOnError: true }
);
assert.ok(formula.includes("katex-mathml"), "KaTeX rendering failed");

const highlight = require(path.join(vendorRoot, "highlight.min.js"));
const highlighted = highlight.highlight("let answer = 42", {
  language: "swift",
});
assert.ok(
  highlighted.value.includes("hljs-keyword"),
  "syntax highlighting failed"
);

console.log(
  `Renderer smoke passed (${fontFiles.length} local KaTeX fonts).`
);
