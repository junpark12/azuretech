(() => {
  "use strict";
  const status = document.getElementById("status");
  const toggle = document.getElementById("theme-toggle");
  const updateThemeLabel = () => {
    const dark = document.documentElement.dataset.theme === "dark";
    toggle.textContent = dark ? "Light theme" : "Dark theme";
    toggle.setAttribute("aria-label", `Switch to ${dark ? "light" : "dark"} theme`);
  };
  updateThemeLabel();
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
      const terms = search.value.toLocaleLowerCase("en").trim().split(/\s+/).filter(Boolean);
      let visible = 0;
      for (const card of cards) {
        const text = card.dataset.search.toLocaleLowerCase("en");
        const matches = (category === "All" || card.dataset.category === category) &&
          terms.every(term => text.includes(term));
        card.hidden = !matches;
        if (matches) visible++;
      }
      document.getElementById("result-count").textContent = `${visible} ${visible === 1 ? "topic" : "topics"}`;
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
    button.textContent = "Copy example";
    button.addEventListener("click", async () => {
      try {
        if (!navigator.clipboard) throw new Error("Clipboard API unavailable");
        await navigator.clipboard.writeText(pre.textContent);
        status.textContent = "Example copied. Replace placeholders before use.";
        button.textContent = "Copied";
        window.setTimeout(() => { button.textContent = "Copy example"; }, 1800);
      } catch (error) {
        status.textContent = "Copy unavailable. Select the example text and copy it manually.";
        button.textContent = "Select text to copy";
        console.warn("Clipboard copy failed:", error.message);
      }
    });
    toolbar.append(button);
    pre.before(toolbar);
  });
})();
