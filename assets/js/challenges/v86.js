// Real Linux shell challenge runner (v86).
//
// Boots a small real Linux (buildroot busybox) entirely in the browser via the
// v86 x86->WASM emulator, renders the serial console with xterm.js, and verifies
// a task by running a check command and matching its output. Heavy: this module
// is built as a SEPARATE bundle (priv/static/assets/v86-runner.js) and loaded on
// demand, so normal pages never download it.
//
// Assets (libv86.js, v86.wasm, BIOSes, kernel image, xterm.css) are served from
// /v86/. The kernel image is ~10MB, so the VM only boots when the user clicks
// "Start", not on page load.

import { Terminal } from "../../vendor/xterm/xterm.mjs";

// Where the heavy v86 assets (kernel, wasm, BIOSes, alpine 9p rootfs) live.
// They are NOT in the Docker image; in prod they are served from jsDelivr (the
// kainlite/tr-lab-assets repo). Locally we use the files under /v86. Override
// anytime by setting window.TR_V86_BASE before the runner loads.
const V86_BASE =
  (typeof window !== "undefined" && window.TR_V86_BASE) ||
  (typeof location !== "undefined" &&
  (location.hostname === "localhost" || location.hostname === "127.0.0.1")
    ? "/v86"
    : "https://cdn.jsdelivr.net/gh/kainlite/tr-lab-assets@v1");
const STORAGE_PREFIX = "tr:challenge:";

// Bootable image profiles. A challenge selects one via `image` in its JSON
// (default "buildroot"). All profiles reuse the same v86 kernel (which already
// has 9p support); "alpine" mounts a full Alpine rootfs over 9p and chroots into
// it so real tools (openssh, curl, socat, dig, git, ...) are available.
const IMAGES = {
  buildroot: {
    label: "Start the Linux box (~10 MB, runs in your browser)",
    memory: 128,
    options: {},
    cmdline: "tsc=reliable mitigations=off random.trust_cpu=on",
    // busybox boots straight to a shell prompt
    readyRe: /[#$%]\s$/,
  },
  alpine: {
    label: "Start the Linux box (Alpine + ssh & tools, runs in your browser)",
    memory: 256,
    options: {
      filesystem: {
        basefs: `${V86_BASE}/alpine/fs.json`,
        baseurl: `${V86_BASE}/alpine/base/`,
      },
    },
    cmdline: "tsc=reliable mitigations=off random.trust_cpu=on",
    // when the buildroot prompt appears, drop into the Alpine chroot lab
    bootPromptRe: /~%\s$/,
    setup:
      "mkdir -p /mnt/proc /mnt/sys /mnt/dev; mount -t proc proc /mnt/proc; " +
      "mount -t sysfs sysfs /mnt/sys; mount -t devtmpfs dev /mnt/dev; " +
      "mkdir -p /mnt/dev/pts; mount -t devpts devpts /mnt/dev/pts; " +
      "chroot /mnt /lab-init.sh\n",
    // lab-init prints this once sshd and the shell are ready
    readySentinel: "__LAB_READY__",
  },
};

let libPromise = null;
function loadLibV86() {
  if (window.V86) return Promise.resolve();
  if (!libPromise) {
    libPromise = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = `${V86_BASE}/libv86.js`;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error("failed to load libv86.js"));
      document.head.appendChild(s);
    });
  }
  return libPromise;
}

function ensureXtermCss() {
  if (document.getElementById("tr-xterm-css")) return;
  const link = document.createElement("link");
  link.id = "tr-xterm-css";
  link.rel = "stylesheet";
  link.href = `${V86_BASE}/xterm.css`;
  document.head.appendChild(link);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

class V86Runner {
  constructor(el, def) {
    this.el = el;
    this.def = def;
    this.storageKey = STORAGE_PREFIX + def.id;
    this.solved = this.loadSolved();
    this.emulator = null;
    this.term = null;
    this.capture = "";
    this.ready = false;
    this.setupSent = false;
    this.profile = IMAGES[def.image] || IMAGES.buildroot;
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
    const d = this.def;
    this.el.classList.add("tr-challenge", "tr-v86");
    this.el.innerHTML = `
      <div class="tr-term-bar">
        <span class="tr-term-dots"><i></i><i></i><i></i></span>
        <span class="tr-term-name">${escapeHtml(d.title || "Real Linux shell")}</span>
        <span class="tr-term-steps" data-role="badge">${this.solved ? "solved ✓" : "real VM"}</span>
      </div>
      <div class="tr-term-progress"><span data-role="bar"></span></div>
      <div class="tr-term-task" data-role="instruction">${escapeHtml(d.instruction || "")}</div>
      <div class="tr-v86-screen" data-role="screen">
        <button type="button" class="tr-v86-start" data-role="start">▶ ${escapeHtml(this.profile.label)}</button>
      </div>
      <div class="tr-v86-status" data-role="status"></div>
      <div class="tr-term-foot">
        <div class="tr-term-foot-btns">
          <button type="button" class="tr-term-btn" data-role="verify" disabled>Verify</button>
          <button type="button" class="tr-term-btn" data-role="hint">Hint</button>
          <button type="button" class="tr-term-btn" data-role="reboot" disabled>Reboot</button>
        </div>
        <span class="tr-term-tip">real Linux, runs in your browser</span>
      </div>`;

    this.badgeEl = this.el.querySelector('[data-role="badge"]');
    this.barEl = this.el.querySelector('[data-role="bar"]');
    this.statusEl = this.el.querySelector('[data-role="status"]');
    this.screenEl = this.el.querySelector('[data-role="screen"]');
    this.verifyBtn = this.el.querySelector('[data-role="verify"]');
    this.rebootBtn = this.el.querySelector('[data-role="reboot"]');

    if (this.solved) {
      this.badgeEl.classList.add("tr-term-steps-ok");
      this.el.classList.add("tr-solved");
      this.barEl.style.width = "100%";
    }

    this.el.querySelector('[data-role="start"]').addEventListener("click", () => this.start());
    this.verifyBtn.addEventListener("click", () => this.verify());
    this.rebootBtn.addEventListener("click", () => this.reboot());
    this.el.querySelector('[data-role="hint"]').addEventListener("click", () => {
      if (this.def.hint) this.setStatus(this.def.hint, "hint");
    });
  }

  setStatus(text, kind) {
    this.statusEl.textContent = text;
    this.statusEl.className = "tr-v86-status" + (kind ? " tr-v86-status-" + kind : "");
  }

  start() {
    this.screenEl.innerHTML = "";
    this.setStatus("Downloading the kernel and booting Linux…", "muted");
    if (!this.solved) this.badgeEl.textContent = "booting…";
    this.barEl.style.width = "20%";

    this.term = new Terminal({
      cols: 80,
      rows: 24,
      fontSize: 13,
      fontFamily: '"JetBrains Mono", ui-monospace, monospace',
      cursorBlink: true,
      convertEol: false,
      theme: { background: "#0d0d0d", foreground: "#e6e6e6", cursor: "#38ef7d" },
    });
    this.term.open(this.screenEl);

    const p = this.profile;
    this.emulator = new window.V86({
      wasm_path: `${V86_BASE}/v86.wasm`,
      memory_size: p.memory * 1024 * 1024,
      vga_memory_size: 2 * 1024 * 1024,
      bios: { url: `${V86_BASE}/seabios.bin` },
      vga_bios: { url: `${V86_BASE}/vgabios.bin` },
      bzimage: { url: `${V86_BASE}/buildroot-bzimage68.bin`, async: false },
      filesystem: {},
      cmdline: p.cmdline,
      autostart: true,
      disable_keyboard: true,
      ...p.options,
    });

    this.emulator.add_listener("serial0-output-byte", (byte) => {
      const ch = String.fromCharCode(byte);
      this.term.write(ch);
      this.capture += ch;
      if (this.capture.length > 200000) this.capture = this.capture.slice(-100000);
      this.onSerial();
    });

    this.term.onData((data) => {
      if (this.emulator) this.emulator.serial0_send(data);
    });
  }

  onSerial() {
    if (this.ready) return;
    const p = this.profile;
    // Images that need post-boot setup (e.g. alpine): once the base shell prompt
    // shows, send the setup that chroots into the rich rootfs.
    if (p.setup && !this.setupSent && p.bootPromptRe.test(this.capture.slice(-4))) {
      this.setupSent = true;
      this.setStatus("Starting the lab (ssh + tools)…", "muted");
      this.emulator.serial0_send(p.setup);
      return;
    }
    if (p.readySentinel) {
      if (this.capture.includes(p.readySentinel)) this.onReady();
    } else if (p.readyRe && p.readyRe.test(this.capture.slice(-4))) {
      this.onReady();
    }
  }

  onReady() {
    this.ready = true;
    this.setStatus(
      this.solved
        ? "This challenge is already solved, the box is a fresh throwaway, feel free to poke around."
        : "Booted! This is a real Linux shell. Do the task above, then click Verify.",
      this.solved ? "ok" : "",
    );
    this.verifyBtn.disabled = false;
    this.rebootBtn.disabled = false;
    if (!this.solved) this.badgeEl.textContent = "ready";
    this.barEl.style.width = this.solved ? "100%" : "55%";
    this.term.focus();
    // Optional per-challenge scenario seeding (create files to fix, data to
    // search, etc). Runs once in the shell after the box is ready.
    if (this.def.setup && !this.setupRan) {
      this.setupRan = true;
      setTimeout(() => {
        if (this.emulator) this.emulator.serial0_send(this.def.setup + "\n");
      }, 700);
    }
  }

  async verify() {
    const v = this.def.verify;
    if (!v || !this.emulator) return;
    this.setStatus("Running the check inside the VM…", "muted");
    const start = this.capture.length;
    this.emulator.serial0_send(v.command + "\n");
    await new Promise((r) => setTimeout(r, v.wait_ms || 1500));
    const out = this.capture.slice(start);

    const patterns = (v.expect_all || [v.expect]).filter(Boolean).map((s) => new RegExp(s, "i"));
    const passed = patterns.length > 0 && patterns.every((re) => re.test(out));

    if (passed) {
      this.solved = true;
      this.saveSolved();
      this.badgeEl.textContent = "solved ✓";
      this.badgeEl.classList.add("tr-term-steps-ok");
      this.el.classList.add("tr-solved");
      this.barEl.style.width = "100%";
      this.setStatus(v.success || "Correct, solved!", "ok");
    } else {
      this.setStatus(v.fail || "Not solved yet, check the task and try again.", "err");
    }
  }

  reboot() {
    if (!this.emulator) return;
    this.ready = false;
    this.capture = "";
    this.verifyBtn.disabled = true;
    this.rebootBtn.disabled = true;
    if (this.term) this.term.reset();
    this.setStatus("Rebooting…", "muted");
    try {
      this.emulator.restart();
    } catch (_e) {
      this.setStatus("Reboot not supported, reload the page to restart.", "err");
    }
  }
}

export async function mount(el, def) {
  ensureXtermCss();
  try {
    await loadLibV86();
  } catch (_e) {
    el.classList.add("tr-challenge");
    el.textContent = "Could not load the in-browser Linux runtime.";
    return;
  }
  new V86Runner(el, def).render();
}

window.TrV86 = { mount };
