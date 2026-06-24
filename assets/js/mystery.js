// "Debugging mystery" runner: a choose-your-own-adventure troubleshooting
// scenario. Each node shows a situation (terminal output / observation) and a
// set of choices; choices branch the story. Terminal nodes either solve the
// mystery (you found the root cause) or dead-end with the lesson for that wrong
// turn and a way back. Authored as JSON in priv/static/mysteries/<id>.json and
// embedded with <div phx-hook="Mystery" data-mystery="<id>">.

const STORAGE_PREFIX = "tr:mystery:";

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

class MysteryRunner {
  constructor(el, def) {
    this.el = el;
    this.def = def;
    this.nodes = def.nodes || {};
    this.storageKey = STORAGE_PREFIX + def.id;
    this.solved = this.loadSolved();
  }

  loadSolved() {
    try {
      return !!(JSON.parse(localStorage.getItem(this.storageKey)) || {}).solved;
    } catch (_e) {
      return false;
    }
  }
  saveSolved() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify({ solved: true }));
    } catch (_e) {
      /* storage disabled */
    }
  }

  render() {
    this.el.classList.add("tr-challenge", "tr-scripted", "tr-mystery");
    this.el.innerHTML = `
      <div class="tr-term-bar">
        <span class="tr-term-dots"><i></i><i></i><i></i></span>
        <span class="tr-term-name">${escapeHtml(this.def.title || "Debugging mystery")}</span>
        <span class="tr-term-steps" data-role="badge">${this.solved ? "solved ✓" : "mystery"}</span>
      </div>
      <div class="tr-term-task" data-role="intro">${escapeHtml(this.def.intro || "")}</div>
      <div class="tr-mystery-body" data-role="body"></div>
      <div class="tr-term-foot">
        <div class="tr-term-foot-btns">
          <button type="button" class="tr-term-btn" data-role="restart">Start over</button>
        </div>
        <span class="tr-term-tip">work the problem, pick your next move</span>
      </div>`;

    this.bodyEl = this.el.querySelector('[data-role="body"]');
    this.badgeEl = this.el.querySelector('[data-role="badge"]');
    if (this.solved) this.badgeEl.classList.add("tr-term-steps-ok");
    this.el.querySelector('[data-role="restart"]').addEventListener("click", () => this.goto(this.def.start));
    this.goto(this.def.start);
  }

  goto(id) {
    const node = this.nodes[id];
    if (!node) return;

    this.bodyEl.innerHTML =
      '<div class="tr-mystery-situation"></div>' +
      (node.outcome
        ? `<div class="tr-mystery-outcome tr-mystery-${node.outcome}"></div>`
        : '<div class="tr-mystery-choices"></div>');

    this.bodyEl.querySelector(".tr-mystery-situation").textContent = node.situation || "";

    if (node.outcome) {
      const out = this.bodyEl.querySelector(".tr-mystery-outcome");
      out.textContent =
        node.text || (node.outcome === "solved" ? "Solved!" : "That wasn't it.");
      if (node.outcome === "deadend") {
        const back = document.createElement("button");
        back.type = "button";
        back.className = "tr-term-btn tr-mystery-back";
        back.textContent = "← Back, try another angle";
        back.addEventListener("click", () => this.goto(node.back || this.def.start));
        out.appendChild(back);
      }
      if (node.outcome === "solved" && !this.solved) {
        this.solved = true;
        this.saveSolved();
        this.badgeEl.textContent = "solved ✓";
        this.badgeEl.classList.add("tr-term-steps-ok");
      }
    } else {
      const wrap = this.bodyEl.querySelector(".tr-mystery-choices");
      (node.choices || []).forEach((c) => {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "tr-mystery-choice";
        b.textContent = c.label;
        b.addEventListener("click", () => this.goto(c.goto));
        wrap.appendChild(b);
      });
    }
  }
}

export function mountMystery(el) {
  const id = el.getAttribute("data-mystery");
  if (!id) return;
  fetch(`/mysteries/${id}.json`)
    .then((r) => r.json())
    .then((def) => new MysteryRunner(el, def).render())
    .catch(() => {
      el.classList.add("tr-challenge");
      el.textContent = "Could not load this debugging mystery.";
    });
}
