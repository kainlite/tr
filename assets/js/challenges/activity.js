// Lab activity log, kept separate from each challenge's solved-state so it can
// never conflict with the runners' own persistence. Records the FIRST time each
// challenge is solved, bucketed by local day, to drive the streak + heatmap on
// the /labs page.

const COUNTED_KEY = "tr:lab-counted";
const ACTIVITY_KEY = "tr:lab-activity";

export function todayKey(d = new Date()) {
  const p = (n) => String(n).padStart(2, "0");
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}

export function recordSolve(id) {
  if (!id) return;
  try {
    const counted = new Set(JSON.parse(localStorage.getItem(COUNTED_KEY) || "[]"));
    if (counted.has(id)) return; // each challenge contributes once
    counted.add(id);
    localStorage.setItem(COUNTED_KEY, JSON.stringify([...counted]));

    const log = JSON.parse(localStorage.getItem(ACTIVITY_KEY) || "{}");
    const key = todayKey();
    log[key] = (log[key] || 0) + 1;
    localStorage.setItem(ACTIVITY_KEY, JSON.stringify(log));
  } catch (_e) {
    /* private mode / storage disabled */
  }
}

export function activityLog() {
  try {
    return JSON.parse(localStorage.getItem(ACTIVITY_KEY) || "{}");
  } catch (_e) {
    return {};
  }
}
