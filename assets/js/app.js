// app.js
// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import * as CookieConsent from "../vendor/cookieconsent.esm";
import hljs from "../vendor/highlight.min.js";
import { mountChallenge } from "./challenges/index.js";
import { mountMystery } from "./mystery.js";
import { renderMermaid, mountAsciinema } from "./markdown.js";
import { initPalette } from "./palette.js";
import { initLabRewards } from "./labs-rewards.js";

let Hooks = {};

// Mounts an interactive challenge widget inside a post. The placeholder lives in
// the post markdown as:
//   <div id="..." phx-hook="Challenge" phx-update="ignore"
//        data-challenge="<id>" data-mode="scripted"></div>
// phx-update="ignore" keeps LiveView from patching the widget's DOM.
Hooks.Challenge = {
  mounted() {
    mountChallenge(this.el);
  },
};

Hooks.Mystery = {
  mounted() {
    mountMystery(this.el);
  },
};

// Labs index: reads per-challenge completion from localStorage (the same keys
// the challenge runners write) and decorates the page with checkmarks, per-track
// progress, and an overall counter. Purely client-side, no server round-trip.
Hooks.LabProgress = {
  mounted() {
    this.run();
    this._onFocus = () => this.run();
    window.addEventListener("focus", this._onFocus);
  },
  destroyed() {
    window.removeEventListener("focus", this._onFocus);
  },
  solved(id) {
    try {
      return !!(JSON.parse(localStorage.getItem("tr:challenge:" + id)) || {}).solved;
    } catch (_e) {
      return false;
    }
  },
  run() {
    this.el.querySelectorAll("[data-lab-id]").forEach((a) => {
      const ok = this.solved(a.getAttribute("data-lab-id"));
      a.classList.toggle("lab-done", ok);
      const c = a.querySelector("[data-lab-check]");
      if (c) c.textContent = ok ? "✓" : "○";
    });
    this.el.querySelectorAll("[data-track]").forEach((t) => {
      const labs = t.querySelectorAll("[data-lab-id]");
      const done = [...labs].filter((a) => this.solved(a.getAttribute("data-lab-id"))).length;
      const cnt = t.querySelector("[data-track-count]");
      if (cnt) cnt.textContent = `${done} / ${labs.length}`;
      const bar = t.querySelector("[data-track-bar]");
      if (bar) bar.style.width = labs.length ? Math.round((done / labs.length) * 100) + "%" : "0%";
      const complete = labs.length > 0 && done === labs.length;
      t.classList.toggle("track-complete", complete);
      const rewards = t.querySelector("[data-track-rewards]");
      if (rewards) rewards.hidden = !complete;
    });
    const ids = new Set();
    this.el.querySelectorAll("[data-lab-id]").forEach((a) => ids.add(a.getAttribute("data-lab-id")));
    let done = 0;
    ids.forEach((id) => {
      if (this.solved(id)) done++;
    });
    const total = ids.size;
    const doneEl = this.el.querySelector("[data-labs-done]");
    const totalEl = this.el.querySelector("[data-labs-total]");
    const barEl = this.el.querySelector("[data-labs-bar]");
    if (doneEl) doneEl.textContent = done;
    if (totalEl) totalEl.textContent = total;
    if (barEl) barEl.style.width = total ? Math.round((done / total) * 100) + "%" : "0%";

    this.renderActivity();
  },
  fmt(d) {
    const p = (n) => String(n).padStart(2, "0");
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
  },
  // current streak: consecutive active days ending today/yesterday, with one
  // "freeze" so a single missed day does not reset it.
  streak(dates) {
    const dayMs = 86400000;
    let cursor = new Date();
    cursor.setHours(0, 0, 0, 0);
    if (!dates.has(this.fmt(cursor))) cursor = new Date(cursor.getTime() - dayMs);
    let s = 0;
    let frozen = false;
    while (true) {
      if (dates.has(this.fmt(cursor))) {
        s++;
        cursor = new Date(cursor.getTime() - dayMs);
      } else if (!frozen && s > 0) {
        frozen = true;
        cursor = new Date(cursor.getTime() - dayMs);
      } else {
        break;
      }
    }
    return s;
  },
  longestStreak(dates) {
    const sorted = [...dates].sort();
    if (!sorted.length) return 0;
    const dayMs = 86400000;
    let best = 1;
    let run = 1;
    for (let i = 1; i < sorted.length; i++) {
      const gap = Math.round((new Date(sorted[i]) - new Date(sorted[i - 1])) / dayMs);
      run = gap === 1 ? run + 1 : 1;
      if (run > best) best = run;
    }
    return best;
  },
  renderActivity() {
    const wrap = this.el.querySelector("[data-streak]");
    if (!wrap) return;
    let log = {};
    try {
      log = JSON.parse(localStorage.getItem("tr:lab-activity") || "{}");
    } catch (_e) {
      /* none */
    }
    const dates = new Set(Object.keys(log));
    const total = Object.values(log).reduce((a, b) => a + b, 0);
    if (total === 0) {
      wrap.hidden = true;
      return;
    }
    wrap.hidden = false;
    const set = (sel, v) => {
      const e = wrap.querySelector(sel);
      if (e) e.textContent = v;
    };
    set("[data-streak-current]", this.streak(dates));
    set("[data-streak-longest]", this.longestStreak(dates));
    set("[data-streak-total]", total);

    const hm = wrap.querySelector("[data-heatmap]");
    if (!hm) return;
    const weeks = 18;
    const dayMs = 86400000;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const start = new Date(today.getTime() - (weeks * 7 - 1) * dayMs);
    start.setDate(start.getDate() - start.getDay());
    const cells = [];
    for (let d = new Date(start); d <= today; d = new Date(d.getTime() + dayMs)) {
      const key = this.fmt(d);
      const n = log[key] || 0;
      const lvl = n === 0 ? 0 : n === 1 ? 1 : n <= 3 ? 2 : 3;
      cells.push(`<span class="tr-hm-cell tr-hm-${lvl}" title="${key}: ${n}"></span>`);
    }
    hm.innerHTML = `<div class="tr-hm-grid">${cells.join("")}</div>`;
  },
};

Hooks.Scroll = {
  mounted() {
    this.el.addEventListener("click", () => {
      document.getElementById("comment_form").scrollIntoView();
    });
  },
};

// Reading-progress rail + TOC scroll-spy for blog posts. Fills the top rail as
// you scroll the article and highlights the current section in the "On this
// page" TOC via an IntersectionObserver on the (enhanced) headings.
Hooks.ReadingProgress = {
  mounted() {
    this.bar = document.querySelector(".tr-progress-rail [data-role='bar']");
    this.headings = Array.from(this.el.querySelectorAll("h2,h3,h4,h5,h6")).filter((h) =>
      h.querySelector(".tr-anchor"),
    );
    this.tocLinks = Array.from(document.querySelectorAll("[data-toc-id]"));
    this._onScroll = () => this.update();
    window.addEventListener("scroll", this._onScroll, { passive: true });
    window.addEventListener("resize", this._onScroll, { passive: true });
    this.setupSpy();
    this.update();
  },
  destroyed() {
    window.removeEventListener("scroll", this._onScroll);
    window.removeEventListener("resize", this._onScroll);
    if (this.observer) this.observer.disconnect();
  },
  update() {
    if (!this.bar) return;
    const rect = this.el.getBoundingClientRect();
    const total = rect.height - window.innerHeight;
    const pct = total > 0 ? Math.min(100, Math.max(0, (-rect.top / total) * 100)) : 0;
    this.bar.style.width = pct + "%";
  },
  setupSpy() {
    if (!this.headings.length || !this.tocLinks.length) return;
    // One heading id can map to several links (the in-article TOC plus the
    // sidebar "On this page"); highlight them all.
    const byId = {};
    this.tocLinks.forEach((a) => {
      const id = a.getAttribute("data-toc-id");
      (byId[id] = byId[id] || []).push(a);
    });
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          this.tocLinks.forEach((a) => a.classList.remove("tr-toc-active"));
          (byId[e.target.id] || []).forEach((a) => a.classList.add("tr-toc-active"));
        });
      },
      { rootMargin: "0px 0px -75% 0px", threshold: 0 },
    );
    this.headings.forEach((h) => this.observer.observe(h));
  },
};

Hooks.CopyHtml = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ text, target }) => {
      if (target !== this.el.id) return;
      const btn = this.el;
      const htmlBlob = new Blob([text], { type: "text/html" });
      const textBlob = new Blob([text], { type: "text/plain" });
      const item = new ClipboardItem({ "text/html": htmlBlob, "text/plain": textBlob });
      if (navigator.clipboard && navigator.clipboard.write && window.isSecureContext) {
        navigator.clipboard.write([item]).then(() => {
          this.flash(btn);
        }).catch(() => {
          this.fallbackCopy(text, btn);
        });
      } else {
        this.fallbackCopy(text, btn);
      }
    });
  },
  flash(btn) {
    const original = btn.innerText;
    btn.innerText = "Copied!";
    setTimeout(() => { btn.innerText = original; }, 1500);
  },
  fallbackCopy(text, btn) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    document.body.removeChild(textarea);
    this.flash(btn);
  },
};

Hooks.CopyToClipboard = {
  mounted() {
    this.run();
  },
  reconnected() {
    this.run();
  },
  run() {
    const copyButtonLabel = "Copy Code";

    // use a class selector if available
    let blocks = document.querySelectorAll("pre");

    blocks.forEach((block) => {
      // only add button if browser supports Clipboard API
      if (navigator.clipboard) {
        let button = document.createElement("button");

        button.innerText = copyButtonLabel;
        block.appendChild(button);

        button.addEventListener("click", async () => {
          await copyCode(block, button);
        });
      }
    });

    async function copyCode(block, button) {
      let code = block.querySelector("code");
      let text = code.innerText;

      try {
        await navigator.clipboard.writeText(text);

        // visual feedback that task is completed
        button.innerText = "Code Copied";

        setTimeout(() => {
          button.innerText = copyButtonLabel;
        }, 700);
      } catch (err) {
        console.error("Failed to copy text: ", err);
        button.innerText = "Copy failed";

        setTimeout(() => {
          button.innerText = copyButtonLabel;
        }, 700);
      }
    }
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => {
  topbar.hide();
  hljs.highlightAll();
  renderMermaid();
  mountAsciinema();
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// Cmd/Ctrl-K command palette
initPalette();

// Per-track certificate + badge rewards on the /labs page
initLabRewards();

liveSocket.disableDebug();
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
  // enable server log streaming to client.
  // disable with reloader.disableServerLogs()
  reloader.enableServerLogs();
});

// https://elixirforum.com/t/how-to-add-dark-mode-for-phoenix-1-7/54356/3
function darkExpected() {
  return (
    localStorage.theme === "dark" ||
    (!("theme" in localStorage) &&
      window.matchMedia("(prefers-color-scheme: dark)").matches)
  );
}

function initDarkMode() {
  // On page load or when changing themes, best to add inline in `head` to avoid FOUC
  if (darkExpected()) {
    document.documentElement.classList.add("dark");
    document.documentElement.classList.add("cc--darkmode");
  } else {
    document.documentElement.classList.remove("dark");
    document.documentElement.classList.remove("cc--darkmode");
  }
}

window.addEventListener("toogle-darkmode", () => {
  if (darkExpected()) {
    localStorage.theme = "light";
    document.documentElement.style.setProperty("color-scheme", "light");
  } else {
    localStorage.theme = "dark";
    document.documentElement.style.setProperty("color-scheme", "dark");
  }
  initDarkMode();
});

initDarkMode();

defaultLanguage = "en";
if (window.location.href.indexOf("/es/") != -1) {
  defaultLanguage = "es";
}

CookieConsent.run({
  guiOptions: {
    consentModal: {
      layout: "box wide",
      position: "bottom right",
      equalWeightButtons: true,
      flipButtons: false,
    },
    preferencesModal: {
      layout: "box",
      position: "right",
      equalWeightButtons: true,
      flipButtons: false,
    },
  },
  categories: {
    necessary: {
      readOnly: true,
    },
  },
  language: {
    default: defaultLanguage,
    autoDetect: "browser",
    translations: {
      es: {
        consentModal: {
          title: "Hola!",
          description:
            "Por favor acepta el uso de cookies para poder seguir navegando en nuestro sitio.",
          acceptAllBtn: "Aceptar todo",
          showPreferencesBtn: "Preferencias",
          footer:
            '<a href="https://segfault.pw/privacy">Politica de privacidad</a>',
        },
        preferencesModal: {
          title: "Consentimiento de cookies",
          acceptAllBtn: "Aceptar todo",
          savePreferencesBtn: "Guardar",
          closeIconLabel: "Cerrar",
          serviceCounterLabel: "Servicio|Servicios",
          sections: [
            {
              title: "Uso de cookies",
              description:
                "Utilizamos unicamente las cookies necesarias para garantizar el correcto funcionamiento del sitio web. Solo hay dos cookies: una para mantener la informacion de su sesion (puramente funcional) y cc_cookie, que se utiliza para guardar sus preferencias de cookies. No servimos anuncios de terceros. Al utilizar este sitio, acepta los terminos de privacidad de este sitio.",
            },
            {
              title: "Mas informacion",
              description:
                'Por cualquier consulta relacionada al sitio o las cookies, por favor contactarnos aqui <a class="cc__link" href="mailto:gabriel@segfault.pw">gabriel@segfault.pw</a>.',
            },
          ],
        },
      },
      en: {
        consentModal: {
          title: "Hello blogger!",
          description:
            "Please accept the usage of cookies to be able to continue browsing our site.",
          acceptAllBtn: "Accept all",
          showPreferencesBtn: "Manage preferences",
          footer: '<a href="https://segfault.pw/privacy">Privacy Policy</a>',
        },
        preferencesModal: {
          title: "Consent Preferences Center",
          acceptAllBtn: "Accept all",
          savePreferencesBtn: "Save preferences",
          closeIconLabel: "Close modal",
          serviceCounterLabel: "Service|Services",
          sections: [
            {
              title: "Cookie Usage",
              description:
                "We use only necessary cookies to ensure the website works properly. There are two cookies: one to maintain your session information (purely functional), and cc_cookie which is used to save your cookie preferences. We do not serve third-party ads. By using this site you are agreeing to the privacy terms from this site.",
            },
            {
              title: "More information",
              description:
                'For any query in relation to my policy on cookies and your choices, please <a class="cc__link" href="mailto:gabriel@segfault.pw">gabriel@segfault.pw</a>.',
            },
          ],
        },
      },
    },
  },
});
