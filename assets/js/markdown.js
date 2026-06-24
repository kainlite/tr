// Client-side rendering of ```mermaid code blocks into diagrams.
//
// Mermaid is large (~2.8MB), so it is lazy-loaded from jsDelivr only when a page
// actually contains a diagram. Diagrams re-render when the site theme toggles so
// they always match light/dark. Authors just write a fenced ```mermaid block.

let mermaidLoad = null;

function loadMermaid() {
  if (window.mermaid) return Promise.resolve(window.mermaid);
  if (!mermaidLoad) {
    mermaidLoad = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js";
      s.onload = () => resolve(window.mermaid);
      s.onerror = () => reject(new Error("mermaid failed to load"));
      document.head.appendChild(s);
    });
  }
  return mermaidLoad;
}

function initMermaid(mermaid) {
  const dark = document.documentElement.classList.contains("dark");
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: dark ? "dark" : "neutral",
    fontFamily: '"JetBrains Mono", ui-monospace, monospace',
  });
}

async function toSvg(mermaid, src, seed) {
  const { svg } = await mermaid.render("trmmd-" + seed, src);
  return svg;
}

export async function renderMermaid() {
  const pres = [...document.querySelectorAll("pre")].filter(
    (p) => p.querySelector("code.language-mermaid") && !p.dataset.mmd,
  );
  if (!pres.length) return;

  // hide the raw source immediately so it doesn't flash before the diagram
  pres.forEach((p) => {
    p.dataset.mmd = "pending";
    p.classList.add("tr-mermaid-pending");
  });

  let mermaid;
  try {
    mermaid = await loadMermaid();
  } catch (_e) {
    pres.forEach((p) => p.classList.remove("tr-mermaid-pending"));
    return;
  }
  initMermaid(mermaid);

  let i = 0;
  for (const pre of pres) {
    const src = pre.querySelector("code").textContent;
    try {
      const svg = await toSvg(mermaid, src, Date.now().toString(36) + "-" + i++);
      const wrap = document.createElement("div");
      wrap.className = "tr-mermaid";
      wrap.dataset.mmdSrc = src;
      wrap.innerHTML = svg;
      pre.replaceWith(wrap);
    } catch (_e) {
      // parse error: leave the source visible instead of an empty box
      pre.dataset.mmd = "err";
      pre.classList.remove("tr-mermaid-pending");
    }
  }
  setupThemeSync();
}

// --- asciinema terminal recordings ----------------------------------------
// Authors embed `<div data-asciinema="/casts/foo.cast"></div>`. Optional data
// attributes mirror the player options (data-rows, data-cols, data-autoplay,
// data-loop, data-speed, data-poster, data-idle-time-limit, data-start-at).
let aspLoad = null;

function loadAsciinema() {
  if (window.AsciinemaPlayer) return Promise.resolve(window.AsciinemaPlayer);
  if (!aspLoad) {
    aspLoad = new Promise((resolve, reject) => {
      if (!document.getElementById("tr-asciinema-css")) {
        const link = document.createElement("link");
        link.id = "tr-asciinema-css";
        link.rel = "stylesheet";
        link.href = "https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.min.css";
        document.head.appendChild(link);
      }
      const s = document.createElement("script");
      s.src = "https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.min.js";
      s.onload = () => resolve(window.AsciinemaPlayer);
      s.onerror = () => reject(new Error("asciinema-player failed to load"));
      document.head.appendChild(s);
    });
  }
  return aspLoad;
}

export async function mountAsciinema() {
  const els = [...document.querySelectorAll("[data-asciinema]")].filter((e) => !e.dataset.aspDone);
  if (!els.length) return;

  let ASP;
  try {
    ASP = await loadAsciinema();
  } catch (_e) {
    return;
  }

  for (const el of els) {
    el.dataset.aspDone = "1";
    const d = el.dataset;
    const opts = {
      theme: "asciinema",
      fit: "width",
      controls: true,
      terminalFontFamily: '"JetBrains Mono", ui-monospace, monospace',
    };
    if (d.rows) opts.rows = parseInt(d.rows, 10);
    if (d.cols) opts.cols = parseInt(d.cols, 10);
    if (d.autoplay !== undefined) opts.autoPlay = true;
    if (d.loop !== undefined) opts.loop = true;
    if (d.speed) opts.speed = parseFloat(d.speed);
    if (d.poster) opts.poster = d.poster;
    if (d.idleTimeLimit) opts.idleTimeLimit = parseFloat(d.idleTimeLimit);
    if (d.startAt) opts.startAt = d.startAt;
    try {
      ASP.create(el.getAttribute("data-asciinema"), el, opts);
    } catch (_e) {
      /* leave the empty container if creation fails */
    }
  }
}

let themeSyncSet = false;
function setupThemeSync() {
  if (themeSyncSet) return;
  themeSyncSet = true;
  let last = document.documentElement.classList.contains("dark");

  new MutationObserver(async () => {
    const dark = document.documentElement.classList.contains("dark");
    if (dark === last) return;
    last = dark;
    const wraps = [...document.querySelectorAll(".tr-mermaid[data-mmd-src]")];
    if (!wraps.length || !window.mermaid) return;
    initMermaid(window.mermaid);
    let i = 0;
    for (const wrap of wraps) {
      try {
        wrap.innerHTML = await toSvg(window.mermaid, wrap.dataset.mmdSrc, "re-" + i++);
      } catch (_e) {
        /* keep the previous render on error */
      }
    }
  }).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
}
