import assert from "node:assert/strict";
import { test } from "node:test";
import { looksLikeStrip, turn } from "../dist/index.js";

const page = (width, height) => ({ width, height });

test("pages much taller than wide are a strip", () => {
    assert.equal(looksLikeStrip([page(800, 12000), page(800, 9000), page(800, 1100)]), true);
});

test("a strip cut into short pieces of one width is still a strip", () => {
    // Under twice as tall as wide, which the old rule took for pages.
    assert.equal(looksLikeStrip([page(720, 1280), page(720, 1280), page(720, 1280), page(720, 1280)]), true);
    assert.equal(looksLikeStrip([page(800, 1000), page(800, 1400), page(800, 900), page(800, 1390)]), true);
});

test("manga and comic pages are pages", () => {
    assert.equal(looksLikeStrip([page(1115, 1600), page(1115, 1600), page(1115, 1600), page(1115, 1600)]), false);
    assert.equal(looksLikeStrip([page(1988, 3056), page(1988, 3056), page(1988, 3056)]), false);
});

test("a spread among pages doesn't make them a strip", () => {
    assert.equal(looksLikeStrip([page(1115, 1600), page(2230, 1600), page(1115, 1600), page(1115, 1600)]), false);
});

test("pages of slightly different scans stay pages", () => {
    assert.equal(looksLikeStrip([page(1100, 1600), page(1120, 1590), page(1108, 1610), page(1115, 1600)]), false);
});

test("nothing to look at isn't a strip", () => {
    assert.equal(looksLikeStrip([]), false);
    assert.equal(looksLikeStrip([page(0, 0)]), false);
});

const around = { next: undefined, previous: 8, first: 0, last: 9 };
const both = { before: true, after: true };

test("a turn past the last page steps onto what's after it, and the next one leaves", () => {
    assert.deepEqual(turn({ start: 9, edge: null }, 1, around, both), { kind: "edge", edge: "after" });
    assert.deepEqual(turn({ start: 9, edge: "after" }, 1, around, both), { kind: "leave", toward: "after" });
});

test("turning back from what's after returns to the last page, not the one before it", () => {
    assert.deepEqual(turn({ start: 9, edge: "after" }, -1, around, both), { kind: "pages", start: 9 });
});

test("the start mirrors the end", () => {
    const first = { next: 1, previous: undefined, first: 0, last: 9 };
    assert.deepEqual(turn({ start: 0, edge: null }, -1, first, both), { kind: "edge", edge: "before" });
    assert.deepEqual(turn({ start: 0, edge: "before" }, -1, first, both), { kind: "leave", toward: "before" });
    assert.deepEqual(turn({ start: 0, edge: "before" }, 1, first, both), { kind: "pages", start: 0 });
});

test("with nothing either side, the pages are all there is", () => {
    const none = { before: false, after: false };
    assert.deepEqual(turn({ start: 9, edge: null }, 1, around, none), { kind: "stay" });
    assert.deepEqual(turn({ start: 0, edge: null }, -1, { ...around, previous: undefined }, none), { kind: "stay" });
});

test("in the middle a turn is a page", () => {
    assert.deepEqual(turn({ start: 4, edge: null }, 1, { next: 5, previous: 3, first: 0, last: 9 }, both), { kind: "pages", start: 5 });
    assert.deepEqual(turn({ start: 4, edge: null }, -1, { next: 5, previous: 3, first: 0, last: 9 }, both), { kind: "pages", start: 3 });
});
