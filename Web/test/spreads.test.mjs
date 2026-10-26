import assert from "node:assert/strict";
import { test } from "node:test";
import { nextScreen, previousScreen, screenPages, screenStart } from "../dist/index.js";

test("the cover stands alone and the rest pair up", () => {
    assert.deepEqual(screenPages(0, 10, true), [0]);
    assert.deepEqual(screenPages(1, 10, true), [1, 2]);
    assert.deepEqual(screenPages(9, 10, true), [9]);
    assert.equal(screenStart(2, true), 1);
    assert.equal(screenStart(4, true), 3);
});

test("turning walks the spreads both ways", () => {
    const forward = [];
    for (let start = 0; start !== undefined; start = nextScreen(start, 7, true)) forward.push(start);
    assert.deepEqual(forward, [0, 1, 3, 5]);
    const back = [];
    for (let start = 5; start !== undefined; start = previousScreen(start, true)) back.push(start);
    assert.deepEqual(back, [5, 3, 1, 0]);
});

test("single pages turn one at a time", () => {
    assert.deepEqual(screenPages(3, 7, false), [3]);
    assert.equal(nextScreen(6, 7, false), undefined);
    assert.equal(previousScreen(0, false), undefined);
});
