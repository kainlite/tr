// Scripted challenge runner.
//
// A lightweight, guided terminal: the learner types commands, each is matched
// against the current step's expected pattern(s), and on a match we print canned
// output and advance. No real execution, ideal for "learn the command" tutorials.
// Real execution is handled by the (heavier) v86 runner.

const STORAGE_PREFIX = "tr:challenge:";

function asRegexList(match) {
  const list = Array.isArray(match) ? match : [match];
  return list.filter(Boolean).map((src) => new RegExp(src, "i"));
}

function allMatch(input, patterns) {
  return patterns.every((re) => re.test(input));
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export class ScriptedRunner {
  constructor(el, def) {
    this.el = el;
    this.def = def;
    this.steps = def.steps || [];
    this.storageKey = STORAGE_PREFIX + def.id;
    const saved = this.load();
    this.stepIndex = saved.solved ? this.steps.length : saved.step || 0;
    this.solved = !!saved.solved;
    this.attempts = 0;
    this.history = [];
    this.histIndex = 0;
  }

  load() {
    try {
      return JSON.parse(localStorage.getItem(this.storageKey)) || {};
    } catch (_e) {
      return {};
    }
  }

  save() {
    try {
      localStorage.setItem(
        this.storageKey,
        JSON.stringify({ step: this.stepIndex, solved: this.solved }),
      );
    } catch (_e) {
      /* private mode / storage disabled */
    }
  }

  render() {
    const d = this.def;
    const prompt = d.prompt || "$ ";
    this.el.classList.add("tr-challenge", "tr-scripted");
    this.el.innerHTML = `
      <div class="tr-term-bar">
        <span class="tr-term-dots"><i></i><i></i><i></i></span>
        <span class="tr-term-name">${escapeHtml(d.title || "Challenge")}</span>
        <span class="tr-term-steps" data-role="steps"></span>
      </div>
      <div class="tr-term-progress"><span data-role="bar"></span></div>
      <div class="tr-term-task" data-role="instruction"></div>
      <div class="tr-term" data-role="term" aria-live="polite">
        <div class="tr-term-out" data-role="out"></div>
        <div class="tr-term-cur">
          <span class="tr-term-ps">${escapeHtml(prompt)}</span>
          <input class="tr-term-in" data-role="input" type="text" spellcheck="false"
                 autocapitalize="off" autocomplete="off" autocorrect="off"
                 aria-label="terminal command input" />
        </div>
      </div>
      <div class="tr-term-foot">
        <div class="tr-term-foot-btns">
          <button type="button" class="tr-term-btn" data-role="hint">Hint</button>
          <button type="button" class="tr-term-btn" data-role="reset">Reset</button>
        </div>
        <span class="tr-term-tip">↑ ↓ history &middot; type <b>help</b> for a hint</span>
      </div>`;

    this.term = this.el.querySelector('[data-role="term"]');
    this.out = this.el.querySelector('[data-role="out"]');
    this.input = this.el.querySelector('[data-role="input"]');
    this.instructionEl = this.el.querySelector('[data-role="instruction"]');
    this.stepsEl = this.el.querySelector('[data-role="steps"]');
    this.barEl = this.el.querySelector('[data-role="bar"]');

    this.input.addEventListener("keydown", (e) => this.onKey(e));
    this.term.addEventListener("mousedown", (e) => {
      // let the user select output text; only focus when clicking empty space
      if (e.target === this.term || e.target === this.out || e.target.classList.contains("tr-term-cur")) {
        e.preventDefault();
        this.input.focus();
      }
    });
    this.el.querySelector('[data-role="hint"]').addEventListener("click", () => this.showHint());
    this.el.querySelector('[data-role="reset"]').addEventListener("click", () => this.reset());

    if (d.intro) this.print(d.intro, "muted");
    if (this.solved) {
      this.print(this.def.done || "Challenge already solved.", "ok");
      this.markSolved();
    } else {
      this.printInstruction();
    }
    this.updateProgress();
  }

  print(text, kind) {
    const line = document.createElement("div");
    line.className = "tr-term-line" + (kind ? " tr-term-" + kind : "");
    line.textContent = text;
    this.out.appendChild(line);
    this.scrollDown();
  }

  scrollDown() {
    this.term.scrollTop = this.term.scrollHeight;
  }

  echo(cmd) {
    this.print((this.def.prompt || "$ ") + cmd, "cmd");
  }

  currentStep() {
    return this.steps[this.stepIndex];
  }

  updateProgress() {
    const total = this.steps.length || 1;
    const done = Math.min(this.stepIndex, total);
    this.barEl.style.width = Math.round((done / total) * 100) + "%";
    if (this.solved) {
      this.stepsEl.textContent = "solved ✓";
      this.stepsEl.className = "tr-term-steps tr-term-steps-ok";
    } else {
      this.stepsEl.textContent = `step ${Math.min(this.stepIndex + 1, total)} / ${total}`;
      this.stepsEl.className = "tr-term-steps";
    }
  }

  printInstruction() {
    const step = this.currentStep();
    if (!step) return;
    this.instructionEl.textContent = step.instruction;
  }

  showHint() {
    const step = this.currentStep();
    if (step && step.hint) this.print("hint: " + step.hint, "hint");
    this.input.focus();
  }

  onKey(e) {
    if (e.key === "Enter") {
      e.preventDefault();
      const v = this.input.value;
      this.input.value = "";
      if (v.trim()) {
        this.history.push(v);
        this.histIndex = this.history.length;
      }
      this.handle(v);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      if (this.histIndex > 0) {
        this.histIndex--;
        this.input.value = this.history[this.histIndex] || "";
        this.moveCaretEnd();
      }
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      if (this.histIndex < this.history.length) {
        this.histIndex++;
        this.input.value = this.history[this.histIndex] || "";
        this.moveCaretEnd();
      }
    }
  }

  moveCaretEnd() {
    const len = this.input.value.length;
    requestAnimationFrame(() => this.input.setSelectionRange(len, len));
  }

  handle(raw) {
    const cmd = (raw || "").trim();
    if (!cmd) return;
    this.echo(cmd);

    if (cmd === "help") return this.showHint();
    if (cmd === "clear") {
      this.out.innerHTML = "";
      return;
    }
    if (cmd === "reset") return this.reset();
    if (this.solved) return;

    const step = this.currentStep();
    if (!step) return;

    if (allMatch(cmd, asRegexList(step.match))) {
      this.attempts = 0;
      if (step.success) this.print(step.success, "ok");
      this.stepIndex += 1;
      this.save();
      this.updateProgress();
      if (this.stepIndex >= this.steps.length) {
        this.print(this.def.done || "Solved!", "ok");
        this.solved = true;
        this.save();
        this.markSolved();
      } else {
        this.printInstruction();
      }
    } else {
      this.attempts += 1;
      this.print(step.fail || "Not quite, that command doesn't satisfy this step.", "err");
      if (this.attempts >= 2 && step.hint) this.print("hint: " + step.hint, "hint");
    }
  }

  markSolved() {
    this.solved = true;
    this.instructionEl.textContent = this.def.done || "Challenge complete.";
    this.instructionEl.classList.add("tr-term-task-ok");
    this.input.setAttribute("placeholder", "solved, type 'reset' to try again");
    this.el.classList.add("tr-solved");
    this.updateProgress();
  }

  reset() {
    this.solved = false;
    this.stepIndex = 0;
    this.attempts = 0;
    this.history = [];
    this.histIndex = 0;
    this.save();
    this.out.innerHTML = "";
    this.el.classList.remove("tr-solved");
    this.instructionEl.classList.remove("tr-term-task-ok");
    this.input.removeAttribute("placeholder");
    if (this.def.intro) this.print(this.def.intro, "muted");
    this.printInstruction();
    this.updateProgress();
    this.input.focus();
  }
}
