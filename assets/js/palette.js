// Cmd/Ctrl-K command palette: quick navigation, post search, and theme/language
// toggles. Post titles come from a small JSON index embedded in the layout, so
// search is instant and client-side.

export function initPalette() {
  const locale = (location.pathname.match(/^\/(en|es)(?:\/|$)/) || [])[1] || "en";
  const other = locale === "en" ? "es" : "en";

  const actions = [
    { label: "Blog", kind: "nav", url: `/${locale}/blog`, icon: "≡" },
    { label: "Search posts", kind: "nav", url: `/${locale}/blog/search`, icon: "⌕" },
    { label: "Tags", kind: "nav", url: `/${locale}/blog/tags`, icon: "#" },
    { label: "Labs", kind: "nav", url: `/${locale}/labs`, icon: "🧪" },
    { label: "About", kind: "nav", url: `/${locale}/about`, icon: "@" },
    { label: "Toggle light / dark theme", kind: "theme", icon: "◐" },
    {
      label: other === "es" ? "Switch to Spanish (ES)" : "Switch to English (EN)",
      kind: "lang",
      icon: "🌐",
    },
  ];

  let posts = [];
  try {
    const el = document.getElementById("tr-post-index");
    if (el) {
      posts = JSON.parse(el.textContent).map((p) => ({
        label: p.t,
        kind: "post",
        url: p.u,
        icon: "›",
      }));
    }
  } catch (_e) {
    /* no index available; nav + toggles still work */
  }

  const root = document.createElement("div");
  root.className = "tr-palette";
  root.hidden = true;
  root.innerHTML = `
    <div class="tr-palette-backdrop" data-role="backdrop"></div>
    <div class="tr-palette-box" role="dialog" aria-label="Command palette">
      <input class="tr-palette-input" data-role="input" type="text"
             placeholder="Jump to a page or search posts…"
             autocomplete="off" autocapitalize="off" spellcheck="false" />
      <ul class="tr-palette-list" data-role="list"></ul>
    </div>`;
  document.body.appendChild(root);

  const input = root.querySelector('[data-role="input"]');
  const list = root.querySelector('[data-role="list"]');
  const backdrop = root.querySelector('[data-role="backdrop"]');
  let results = [];
  let sel = 0;
  let open = false;

  function render() {
    const q = input.value.trim().toLowerCase();
    const acts = q ? actions.filter((a) => a.label.toLowerCase().includes(q)) : actions;
    const ps = q ? posts.filter((p) => p.label.toLowerCase().includes(q)).slice(0, 8) : [];
    results = [...acts, ...ps];
    sel = 0;
    list.innerHTML = results
      .map(
        (r, i) =>
          `<li class="tr-palette-item" data-i="${i}"><span class="tr-palette-icon"></span><span class="tr-palette-label"></span><span class="tr-palette-tag">${r.kind === "post" ? "post" : ""}</span></li>`,
      )
      .join("");
    [...list.children].forEach((li, i) => {
      li.querySelector(".tr-palette-icon").textContent = results[i].icon;
      li.querySelector(".tr-palette-label").textContent = results[i].label;
    });
    highlight();
  }

  function highlight() {
    [...list.children].forEach((li, i) => li.classList.toggle("tr-palette-active", i === sel));
    if (list.children[sel]) list.children[sel].scrollIntoView({ block: "nearest" });
  }

  function activate(item) {
    if (!item) return;
    close();
    if (item.kind === "theme") {
      window.dispatchEvent(new Event("toogle-darkmode"));
      return;
    }
    if (item.kind === "lang") {
      const p = location.pathname;
      location.href = /^\/(en|es)(?:\/|$)/.test(p) ? p.replace(/^\/(en|es)/, "/" + other) : "/" + other + p;
      return;
    }
    location.href = item.url;
  }

  function openPalette() {
    open = true;
    root.hidden = false;
    input.value = "";
    render();
    setTimeout(() => input.focus(), 0);
  }
  function close() {
    open = false;
    root.hidden = true;
  }

  input.addEventListener("input", render);
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      sel = Math.min(results.length - 1, sel + 1);
      highlight();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      sel = Math.max(0, sel - 1);
      highlight();
    } else if (e.key === "Enter") {
      e.preventDefault();
      activate(results[sel]);
    } else if (e.key === "Escape") {
      e.preventDefault();
      close();
    }
  });
  list.addEventListener("click", (e) => {
    const li = e.target.closest("[data-i]");
    if (li) activate(results[+li.dataset.i]);
  });
  backdrop.addEventListener("click", close);

  document.addEventListener(
    "keydown",
    (e) => {
      if ((e.metaKey || e.ctrlKey) && (e.key === "k" || e.key === "K")) {
        e.preventDefault();
        open ? close() : openPalette();
      }
    },
    true,
  );
}
