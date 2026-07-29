"use strict";

(() => {
  try {
  const scrollRoot = document.getElementById("scroll-root");
  const transcript = document.getElementById("transcript");
  const renderKeys = new Map();
  let labels = {
    thinking: "Codex is thinking…",
    copyCode: "Copy",
    copied: "Copied",
    selectedFrom: "Selected from",
    image: "Image",
  };
  let selectionKey = "";

  const markdown = window.markdownit({
    html: false,
    breaks: false,
    linkify: true,
    typographer: false,
    highlight(code, language) {
      if (language && window.hljs.getLanguage(language)) {
        return window.hljs.highlight(code, {
          language,
          ignoreIllegals: true,
        }).value;
      }
      return window.hljs.highlightAuto(code).value;
    },
  });

  const fallbackLinkOpen =
    markdown.renderer.rules.link_open ||
    ((tokens, index, options, _environment, renderer) =>
      renderer.renderToken(tokens, index, options));

  markdown.renderer.rules.link_open = (
    tokens,
    index,
    options,
    environment,
    renderer
  ) => {
    tokens[index].attrSet("target", "_blank");
    tokens[index].attrSet("rel", "noreferrer noopener");
    return fallbackLinkOpen(
      tokens,
      index,
      options,
      environment,
      renderer
    );
  };

  markdown.renderer.rules.fence = (tokens, index, options) => {
    const token = tokens[index];
    const language = token.info.trim().split(/\s+/)[0] || "text";
    const escapedLanguage = markdown.utils.escapeHtml(language);
    const highlighted = options.highlight
      ? options.highlight(token.content, language)
      : markdown.utils.escapeHtml(token.content);

    return [
      '<section class="code-frame">',
      '<div class="code-toolbar">',
      `<span class="code-language">${escapedLanguage}</span>`,
      `<button type="button" class="copy-code" data-copy-code>${markdown.utils.escapeHtml(
        labels.copyCode
      )}</button>`,
      "</div>",
      `<pre><code class="hljs language-${escapedLanguage}">${highlighted}</code></pre>`,
      "</section>",
    ].join("");
  };

  markdown.renderer.rules.image = (tokens, index) => {
    const token = tokens[index];
    const source = token.attrGet("src") || "";
    const alternative = token.content || labels.image;
    const escapedSource = markdown.utils.escapeHtml(source);
    const escapedAlternative = markdown.utils.escapeHtml(alternative);

    if (/^data:image\/(?:png|jpeg|gif|webp);base64,/i.test(source)) {
      return `<img class="inline-image" src="${escapedSource}" alt="${escapedAlternative}">`;
    }

    if (!markdown.validateLink(source)) {
      return `<span class="image-placeholder">${escapedAlternative}</span>`;
    }

    return [
      `<a class="image-link" href="${escapedSource}" target="_blank" rel="noreferrer noopener">`,
      '<span aria-hidden="true">▧</span>',
      `<span>${escapedAlternative || markdown.utils.escapeHtml(labels.image)}</span>`,
      '<span aria-hidden="true">↗</span>',
      "</a>",
    ].join("");
  };

  function normalizeMathDelimiters(source) {
    const lines = source.split("\n");
    let fence = null;
    let prose = [];
    const output = [];

    const flushProse = () => {
      if (prose.length > 0) {
        output.push(normalizeProseMath(prose.join("\n")));
        prose = [];
      }
    };

    lines.forEach((line) => {
      const fenceMatch = line.match(/^\s{0,3}(`{3,}|~{3,})/);
      if (fenceMatch) {
        const marker = fenceMatch[1][0];
        if (fence === null) {
          flushProse();
          fence = marker;
        } else if (fence === marker) {
          fence = null;
        }
        output.push(line);
      } else if (fence === null && !/^(?: {4}|\t)/.test(line)) {
        prose.push(line);
      } else {
        flushProse();
        output.push(line);
      }
    });

    flushProse();
    return output.join("\n");
  }

  function normalizeProseMath(source) {
    let output = "";
    let cursor = 0;

    while (cursor < source.length) {
      if (source[cursor] === "`") {
        const start = cursor;
        while (source[cursor] === "`") {
          cursor += 1;
        }
        const tickCount = cursor - start;
        const closing = source.indexOf("`".repeat(tickCount), cursor);
        if (closing === -1) {
          return output + source.slice(start);
        }
        output += source.slice(start, closing + tickCount);
        cursor = closing + tickCount;
        continue;
      }

      const opener = source.slice(cursor, cursor + 2);
      if (opener === "\\(" || opener === "\\[") {
        const closer = opener === "\\(" ? "\\)" : "\\]";
        const closing = source.indexOf(closer, cursor + 2);
        if (closing !== -1) {
          const delimiter = opener === "\\(" ? "$" : "$$";
          output +=
            delimiter +
            source.slice(cursor + 2, closing) +
            delimiter;
          cursor = closing + 2;
          continue;
        }
      }

      output += source[cursor];
      cursor += 1;
    }

    return output;
  }

  function decorateRenderedContent(container) {
    container.querySelectorAll("table").forEach((table) => {
      if (table.parentElement?.classList.contains("table-scroll")) {
        return;
      }
      const wrapper = document.createElement("div");
      wrapper.className = "table-scroll";
      table.replaceWith(wrapper);
      wrapper.appendChild(table);
    });

    container.querySelectorAll("li").forEach((item) => {
      const content =
        item.firstElementChild?.tagName === "P"
          ? item.firstElementChild
          : item;
      const walker = document.createTreeWalker(
        content,
        NodeFilter.SHOW_TEXT
      );
      const firstText = walker.nextNode();
      const match = firstText?.textContent?.match(/^\s*\[([ xX])\]\s+/);
      if (!match) {
        return;
      }
      firstText.textContent = firstText.textContent.slice(match[0].length);
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.disabled = true;
      checkbox.checked = match[1].toLowerCase() === "x";
      checkbox.setAttribute(
        "aria-label",
        checkbox.checked ? "Completed" : "Not completed"
      );
      content.prepend(checkbox);
      item.classList.add("task-item");
      item.parentElement?.classList.add("task-list");
    });

    container.querySelectorAll("pre > code:not(.hljs)").forEach((code) => {
      window.hljs.highlightElement(code);
    });

    window.renderMathInElement(container, {
      delimiters: [
        { left: "$$", right: "$$", display: true },
        { left: "$", right: "$", display: false },
      ],
      ignoredTags: [
        "script",
        "noscript",
        "style",
        "textarea",
        "pre",
        "code",
      ],
      throwOnError: false,
      strict: "ignore",
      trust: false,
    });
  }

  function renderMarkdown(container, source) {
    container.innerHTML = markdown.render(
      normalizeMathDelimiters(source || "")
    );
    decorateRenderedContent(container);
  }

  function buildSelection(selection) {
    const card = document.createElement("section");
    card.id = "selection-card";
    card.className = "selection-card";

    const source = document.createElement("div");
    source.className = "selection-source";
    source.textContent = `${labels.selectedFrom} ${selection.source}`;

    const quotation = document.createElement("blockquote");
    quotation.textContent = selection.preview;

    card.append(source, quotation);
    return card;
  }

  function updateSelection(selection) {
    const nextKey = selection
      ? `${selection.source}\u0000${selection.preview}`
      : "";
    if (nextKey === selectionKey) {
      return;
    }
    selectionKey = nextKey;
    document.getElementById("selection-card")?.remove();
    if (selection) {
      transcript.prepend(buildSelection(selection));
    }
  }

  function buildMessage(message) {
    const article = document.createElement("article");
    article.className = `message ${message.role}`;
    article.dataset.messageId = message.id;

    if (message.role === "assistant") {
      const mark = document.createElement("span");
      mark.className = "assistant-mark";
      mark.setAttribute("aria-hidden", "true");
      article.appendChild(mark);
    }

    const body = document.createElement("div");
    body.className = "message-body";
    article.appendChild(body);
    return article;
  }

  function updateMessage(element, message) {
    const nextKey = `${message.text}\u0000${message.isStreaming}`;
    if (renderKeys.get(message.id) === nextKey) {
      return;
    }
    renderKeys.set(message.id, nextKey);
    element.className = `message ${message.role}${
      message.isStreaming ? " streaming" : ""
    }`;

    const body = element.querySelector(".message-body");
    if (message.isStreaming && message.text.length === 0) {
      body.innerHTML = "";
      const thinking = document.createElement("div");
      thinking.className = "thinking";
      thinking.innerHTML =
        '<span class="thinking-dots" aria-hidden="true"><i></i><i></i><i></i></span>';
      const text = document.createElement("span");
      text.textContent = labels.thinking;
      thinking.appendChild(text);
      body.appendChild(thinking);
      return;
    }

    renderMarkdown(body, message.text);
  }

  function updateMessages(messages) {
    const activeIDs = new Set(messages.map((message) => message.id));

    transcript.querySelectorAll("[data-message-id]").forEach((element) => {
      if (!activeIDs.has(element.dataset.messageId)) {
        renderKeys.delete(element.dataset.messageId);
        element.remove();
      }
    });

    messages.forEach((message) => {
      let element = transcript.querySelector(
        `[data-message-id="${CSS.escape(message.id)}"]`
      );
      if (!element) {
        element = buildMessage(message);
        transcript.appendChild(element);
      } else {
        transcript.appendChild(element);
      }
      updateMessage(element, message);
    });
  }

  function render(payload) {
    document.querySelector(".renderer-loading")?.remove();
    const distanceFromBottom =
      scrollRoot.scrollHeight -
      scrollRoot.scrollTop -
      scrollRoot.clientHeight;
    const shouldStickToBottom =
      distanceFromBottom < 112 || renderKeys.size === 0;

    labels = { ...labels, ...(payload.labels || {}) };
    updateSelection(payload.selection || null);
    updateMessages(payload.messages || []);

    if (shouldStickToBottom) {
      requestAnimationFrame(() => {
        scrollRoot.scrollTop = scrollRoot.scrollHeight;
      });
    }
  }

  document.addEventListener("click", (event) => {
    const copyButton = event.target.closest("[data-copy-code]");
    if (copyButton) {
      const code =
        copyButton.closest(".code-frame")?.querySelector("code")
          ?.textContent || "";
      window.webkit?.messageHandlers?.copyCode?.postMessage(code);
      copyButton.textContent = labels.copied;
      copyButton.classList.add("copied");
      window.setTimeout(() => {
        copyButton.textContent = labels.copyCode;
        copyButton.classList.remove("copied");
      }, 1200);
      return;
    }

    const link = event.target.closest("a[href]");
    if (link) {
      event.preventDefault();
      window.webkit?.messageHandlers?.openLink?.postMessage(link.href);
    }
  });

  window.glosslet = { render };
  window.webkit?.messageHandlers?.rendererReady?.postMessage(true);
  } catch (error) {
    const fallback = document.getElementById("transcript");
    if (fallback) {
      fallback.textContent = `Renderer error: ${String(
        error?.message || error
      )}`;
    }
    window.webkit?.messageHandlers?.rendererReady?.postMessage(false);
  }
})();
