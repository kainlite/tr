// Challenge mount entry point.
//
// Reads the placeholder's data-* attributes, loads the challenge definition
// (static JSON under /challenges/<id>.json), and hands off to the runner that
// matches the requested mode. Only the lightweight "scripted" runner is bundled
// here; heavier runners (a real Linux VM via v86) are loaded on demand later.

import { ScriptedRunner } from "./scripted.js";

async function loadDefinition(id) {
  const res = await fetch(`/challenges/${encodeURIComponent(id)}.json`, {
    headers: { Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`challenge "${id}" not found (${res.status})`);
  return res.json();
}

// The v86 (real Linux VM) runner is heavy, so it lives in a separate bundle that
// we only fetch when a v86-mode challenge is actually on the page.
let v86Promise = null;
function loadV86Runner() {
  if (window.TrV86) return Promise.resolve(window.TrV86);
  if (!v86Promise) {
    v86Promise = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "/assets/v86-runner.js";
      s.onload = () => resolve(window.TrV86);
      s.onerror = () => reject(new Error("failed to load v86-runner.js"));
      document.head.appendChild(s);
    });
  }
  return v86Promise;
}

export async function mountChallenge(el) {
  if (el.dataset.mounted) return;
  el.dataset.mounted = "1";

  const id = el.dataset.challenge;
  const mode = el.dataset.mode || "scripted";
  if (!id) return;

  let def;
  try {
    def = await loadDefinition(id);
  } catch (err) {
    el.classList.add("tr-challenge");
    el.textContent = "This interactive challenge could not be loaded.";
    console.error("[challenge]", err);
    return;
  }

  const effectiveMode = mode || def.mode || "scripted";
  if (effectiveMode === "scripted") {
    new ScriptedRunner(el, def).render();
  } else if (effectiveMode === "v86") {
    try {
      const TrV86 = await loadV86Runner();
      await TrV86.mount(el, def);
    } catch (err) {
      el.classList.add("tr-challenge");
      el.textContent = "The in-browser Linux environment could not be loaded.";
      console.error("[challenge:v86]", err);
    }
  } else {
    el.classList.add("tr-challenge");
    el.textContent = `Interactive mode "${effectiveMode}" is not available yet.`;
  }
}
