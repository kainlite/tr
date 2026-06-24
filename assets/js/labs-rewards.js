// Per-track rewards on /labs: a downloadable completion certificate (PNG,
// generated client-side) and an embeddable badge snippet. The rewards block is
// revealed by the LabProgress hook once a learning track is fully solved.

export function initLabRewards() {
  const root = document.getElementById("labs-root");
  if (!root) return;
  root.addEventListener("click", (e) => {
    const cert = e.target.closest("[data-cert]");
    if (cert) return downloadCertificate(cert.dataset.trackTitle);
    const badge = e.target.closest("[data-copy-badge]");
    if (badge) return copyBadge(badge);
  });
}

function flash(btn, msg) {
  const orig = btn.textContent;
  btn.textContent = msg;
  setTimeout(() => {
    btn.textContent = orig;
  }, 1300);
}

function copyBadge(btn) {
  const url = `${location.origin}/labs/badge/${btn.dataset.trackSlug}.svg`;
  const md = `[![${btn.dataset.trackTitle}](${url})](${location.origin}/labs)`;
  navigator.clipboard.writeText(md).then(
    () => flash(btn, "✓ Copied markdown"),
    () => flash(btn, "Copy failed"),
  );
}

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function certSvg(title, name) {
  const date = new Date().toLocaleDateString(undefined, {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  const shift = name ? 0 : -55;
  const nameBlock = name
    ? `<text x="600" y="395" fill="#ffffff" font-family="monospace" font-size="46" text-anchor="middle">${esc(name)}</text>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="850" viewBox="0 0 1200 850">
    <rect width="1200" height="850" fill="#0d0d0d"/>
    <rect x="28" y="28" width="1144" height="794" fill="none" stroke="#38ef7d" stroke-width="3" rx="12"/>
    <text x="600" y="170" fill="#38ef7d" font-family="monospace" font-size="36" text-anchor="middle">$ SegFault Labs</text>
    <text x="600" y="285" fill="#e6e6e6" font-family="monospace" font-size="30" text-anchor="middle">Certificate of Completion</text>
    ${nameBlock}
    <text x="600" y="${475 + shift}" fill="#bbbbbb" font-family="monospace" font-size="24" text-anchor="middle">${name ? "has completed the" : "Awarded for completing the"}</text>
    <text x="600" y="${555 + shift}" fill="#38ef7d" font-family="monospace" font-size="44" text-anchor="middle">${esc(title)}</text>
    <text x="600" y="${610 + shift}" fill="#bbbbbb" font-family="monospace" font-size="24" text-anchor="middle">learning track</text>
    <text x="600" y="760" fill="#888888" font-family="monospace" font-size="20" text-anchor="middle">${date}  ·  segfault.pw/labs</text>
  </svg>`;
}

function downloadCertificate(title) {
  const name = (window.prompt("Name to put on the certificate (optional):", "") || "").trim();
  const url = URL.createObjectURL(new Blob([certSvg(title, name)], { type: "image/svg+xml" }));
  const img = new Image();
  img.onload = () => {
    const canvas = document.createElement("canvas");
    canvas.width = 1200;
    canvas.height = 850;
    canvas.getContext("2d").drawImage(img, 0, 0, 1200, 850);
    URL.revokeObjectURL(url);
    canvas.toBlob((blob) => {
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download =
        "segfault-labs-" +
        title
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-|-$/g, "") +
        "-certificate.png";
      document.body.appendChild(a);
      a.click();
      a.remove();
    });
  };
  img.onerror = () => window.alert("Could not generate the certificate image.");
  img.src = url;
}
