(() => {
  "use strict";
  const status = document.getElementById("status");
  const toggle = document.getElementById("theme-toggle");
  const locale = document.documentElement.lang === "ko" ? "ko" : "en";
  const text = locale === "ko" ? {
    light: "밝은 테마", dark: "어두운 테마",
    copy: "예제 복사", copied: "복사됨",
    copySuccess: "예제를 복사했습니다. 사용 전에 자리표시자를 바꾸세요.",
    copyFailed: "복사할 수 없습니다. 예제 텍스트를 선택해 직접 복사하세요.",
    select: "텍스트 선택 후 복사"
  } : {
    light: "Light theme", dark: "Dark theme",
    copy: "Copy example", copied: "Copied",
    copySuccess: "Example copied. Replace placeholders before use.",
    copyFailed: "Copy unavailable. Select the example text and copy it manually.",
    select: "Select text to copy"
  };
  const languageLinks = Array.from(document.querySelectorAll(".language-link"));
  const sections = Array.from(document.querySelectorAll(".article h2[id], .article h3[id], .article h4[id], .article figure[id]"));
  let readingHash = window.location.hash;
  const updateLanguageLinks = () => {
    for (const link of languageLinks) {
      const url = new URL(link.href);
      url.hash = readingHash;
      url.searchParams.set("scoutTheme", document.documentElement.dataset.theme);
      link.href = url.href;
    }
  };
  const updateThemeLabel = () => {
    const dark = document.documentElement.dataset.theme === "dark";
    toggle.textContent = dark ? text.light : text.dark;
    toggle.setAttribute("aria-label", locale === "ko"
      ? `${dark ? text.light : text.dark}로 전환`
      : `Switch to ${dark ? "light" : "dark"} theme`);
    updateLanguageLinks();
  };
  updateThemeLabel();
  window.addEventListener("hashchange", () => {
    readingHash = window.location.hash;
    updateLanguageLinks();
  });
  const updateReadingSection = () => {
    const scrollPadding = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop);
    const threshold = Math.max(scrollPadding + 4, document.querySelector(".site-header").getBoundingClientRect().bottom + 8);
    const current = sections.filter(section => section.getBoundingClientRect().top <= threshold).pop();
    // Keep the last reading section when returning above the article to the language selector.
    if (current) {
      readingHash = `#${current.id}`;
      updateLanguageLinks();
    }
  };
  let scrollPending = false;
  window.addEventListener("scroll", () => {
    if (scrollPending) return;
    scrollPending = true;
    window.requestAnimationFrame(() => {
      updateReadingSection();
      scrollPending = false;
    });
  }, { passive: true });
  const sectionIndex = document.querySelector(".toc details");
  if (sectionIndex && window.matchMedia("(max-width: 720px)").matches) {
    sectionIndex.open = false;
  }
  toggle.addEventListener("click", () => {
    const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = theme;
    const url = new URL(window.location.href);
    url.searchParams.set("scoutTheme", theme);
    window.history.replaceState(null, "", url);
    updateThemeLabel();
  });
  // Preserve the selected theme on local navigation without cookies or storage.
  document.addEventListener("click", event => {
    if (!(event.target instanceof Element)) return;
    const link = event.target.closest("a[href]");
    if (!link || link.hasAttribute("download")) return;
    const href = link.getAttribute("href");
    if (href.startsWith("#")) return;
    const url = new URL(href, window.location.href);
    if (url.origin === window.location.origin && url.pathname.endsWith(".html")) {
      url.searchParams.set("scoutTheme", document.documentElement.dataset.theme);
      link.href = url.href;
    }
  });

  const search = document.getElementById("search");
  if (search) {
    const cards = Array.from(document.querySelectorAll(".topic-card"));
    const filters = Array.from(document.querySelectorAll(".filter"));
    let category = "All";
    const applyFilters = () => {
      const terms = search.value.normalize("NFC").toLocaleLowerCase(locale).trim().split(/\s+/).filter(Boolean);
      let visible = 0;
      for (const card of cards) {
        const text = card.dataset.search.normalize("NFC").toLocaleLowerCase(locale);
        const matches = (category === "All" || card.dataset.category === category) &&
          terms.every(term => text.includes(term));
        card.hidden = !matches;
        if (matches) visible++;
      }
      document.getElementById("result-count").textContent = locale === "ko"
        ? `${visible}개 주제` : `${visible} ${visible === 1 ? "topic" : "topics"}`;
      document.getElementById("empty-state").hidden = visible !== 0;
    };
    search.addEventListener("input", applyFilters);
    filters.forEach(button => button.addEventListener("click", () => {
      category = button.dataset.filter;
      filters.forEach(filter => {
        const active = filter === button;
        filter.classList.toggle("active", active);
        filter.setAttribute("aria-pressed", String(active));
      });
      applyFilters();
    }));
  }

  document.querySelectorAll(".article-body pre").forEach(pre => {
    const toolbar = document.createElement("div");
    toolbar.className = "code-toolbar";
    const button = document.createElement("button");
    button.type = "button";
    button.className = "copy-code";
    button.textContent = text.copy;
    button.addEventListener("click", async () => {
      try {
        if (!navigator.clipboard) throw new Error("Clipboard API unavailable");
        await navigator.clipboard.writeText(pre.textContent);
        status.textContent = text.copySuccess;
        button.textContent = text.copied;
        window.setTimeout(() => { button.textContent = text.copy; }, 1800);
      } catch (error) {
        status.textContent = text.copyFailed;
        button.textContent = text.select;
        console.warn("Clipboard copy failed:", error.message);
      }
    });
    toolbar.append(button);
    pre.before(toolbar);
  });
})();
