// node dock/test.js
const fs = require("fs");
eval(fs.readFileSync(__dirname + "/logic.js", "utf8").replace(".pragma library", ""));
const assert = require("assert");

const apps = groupApps(["a", "b"], [{ key: "c" }, { key: "a" }, { key: "c" }]);
assert.deepStrictEqual(apps.map(a => [a.key, a.pinned, a.windows.length]),
    [["a", true, 1], ["b", true, 0], ["c", false, 2]]);

assert.strictEqual(scaleAt(0, 48, 72, 150), 1.5);
assert.strictEqual(scaleAt(150, 48, 72, 150), 1);

// At rest the row is untouched.
const rest = layout([56, 56, 16, 56], [true, true, false, true], null, 0, 48, 72, 150);
assert.deepStrictEqual(rest.x, [0, 56, 112, 128]);
assert.strictEqual(rest.end, 184);

// Hovered: the point under the pointer stays put, the divider never grows.
const m = 20;
const hov = layout([56, 56, 16, 56], [true, true, false, true], m, 1, 48, 72, 150);
assert(Math.abs(hov.x[0] + (m / 56) * hov.w[0] - m) < 1e-9);
assert.strictEqual(hov.w[2], 16);
assert(hov.w[0] > hov.w[1] && hov.w[1] > 56);


// Dragging slot 0 to position 2: slots 1 and 2 shift left, the rest stay.
assert.deepStrictEqual([0, 1, 2, 3].map(i => dragPos(i, 0, 2)), [2, 0, 1, 3]);
assert.deepStrictEqual([0, 1, 2, 3].map(i => dragPos(i, 3, 1)), [0, 2, 3, 1]);
assert.deepStrictEqual([0, 1, 2].map(i => dragPos(i, -1, 0)), [0, 1, 2]);

// Pinned a, b; running c. Drag c to the front: it gets pinned first.
assert.deepStrictEqual(pinsAfterDrop(["a", "b", "c"], ["a", "b"], 2, 0, true), ["c", "a", "b"]);
// Reorder pins.
assert.deepStrictEqual(pinsAfterDrop(["a", "b", "c"], ["a", "b"], 0, 1, true), ["b", "a"]);
// An app with no desktop file can't be pinned.
assert.deepStrictEqual(pinsAfterDrop(["a", "c"], ["a"], 1, 0, false), ["a"]);
console.log("ok");
