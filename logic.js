// Pure logic for Service.qml — no Quickshell imports so it stays testable.
.pragma library

// Pinned apps first in pin order, then running unpinned apps in first-seen
// order. windows: [{ key, ... }] → [{ key, pinned, windows: [...] }].
function groupApps(pinned, windows) {
    const byKey = {};
    const apps = [];
    for (const key of pinned) {
        if (byKey[key]) continue;
        byKey[key] = { key: key, pinned: true, windows: [] };
        apps.push(byKey[key]);
    }
    for (const w of windows) {
        if (!byKey[w.key]) {
            byKey[w.key] = { key: w.key, pinned: false, windows: [] };
            apps.push(byKey[w.key]);
        }
        byKey[w.key].windows.push(w);
    }
    return apps;
}

// macOS magnification: a raised cosine around the pointer. 1 at `range` away,
// max/base right under it.
function scaleAt(dist, base, max, range) {
    if (dist >= range) return 1;
    return 1 + (max / base - 1) * (Math.cos(Math.PI * dist / range) + 1) / 2;
}

// Lay out a row of slots. widths are the resting slot widths; scalable[i]
// false keeps a slot (the divider) at its resting width. mouse is the pointer
// in resting-row coordinates, or null; amount (0..1) fades magnification in and
// out. The row is shifted so the point under the pointer stays under it, which
// is why the dock grows unevenly when you hover near one end, like macOS.
// Returns positions relative to the resting row's left edge.
function layout(widths, scalable, mouse, amount, base, max, range) {
    const x = [], w = [], s = [];
    let rest = 0, pos = 0, anchor = null;
    for (let i = 0; i < widths.length; i++) {
        const center = rest + widths[i] / 2;
        const full = (mouse === null || !scalable[i]) ? 1 : scaleAt(Math.abs(mouse - center), base, max, range);
        const scale = 1 + (full - 1) * amount;
        const width = widths[i] * scale;
        if (mouse !== null && mouse >= rest && mouse < rest + widths[i])
            anchor = pos + (mouse - rest) / widths[i] * width;
        x.push(pos); w.push(width); s.push(scale);
        rest += widths[i];
        pos += width;
    }
    // Pointer off the row (or none): grow evenly about the centre.
    const shift = anchor !== null ? mouse - anchor : (rest - pos) / 2;
    for (let i = 0; i < x.length; i++) x[i] += shift;
    return { x: x, w: w, s: s, start: shift, end: shift + pos };
}

// Where slot i sits while slot `from` is dragged to position `to`.
function dragPos(i, from, to) {
    if (from < 0 || i === from) return from < 0 ? i : to;
    if (from < to && i > from && i <= to) return i - 1;
    if (to < from && i >= to && i < from) return i + 1;
    return i;
}

// Pins after dropping app `from` at position `to`. A dropped app is kept in
// the dock (if it can be launched); pins keep the new on-screen order.
function pinsAfterDrop(keys, pinned, from, to, canPin) {
    const order = keys.slice();
    const [moved] = order.splice(from, 1);
    order.splice(to, 0, moved);
    const keep = new Set(pinned);
    if (canPin) keep.add(moved);
    return order.filter(k => keep.has(k));
}
