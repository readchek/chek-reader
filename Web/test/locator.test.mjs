import assert from "node:assert/strict";
import { test } from "node:test";
import { comicLocator, comicPageIndex } from "../dist/index.js";

test("a comic locator names its page as the Swift package does", () => {
    assert.deepEqual(comicLocator(4, 20, "image/png"), {
        href: "pages/5",
        type: "image/png",
        locations: { progression: 0, position: 5, totalProgression: 0.2 },
    });
});

test("a locator's page comes from its href first", () => {
    assert.equal(comicPageIndex(comicLocator(9, 20), 20), 9);
    assert.equal(comicPageIndex({ href: "pages/21", type: "image/jpeg" }, 20), undefined);
});

test("older locators fall back to their position, then their progression", () => {
    assert.equal(comicPageIndex({ href: "001.jpg", type: "image/jpeg", locations: { position: 3 } }, 20), 2);
    assert.equal(comicPageIndex({ href: "001.jpg", type: "image/jpeg", locations: { position: 99 } }, 20), 19);
    assert.equal(comicPageIndex({ href: "001.jpg", type: "image/jpeg", locations: { totalProgression: 0.5 } }, 20), 10);
    assert.equal(comicPageIndex({ href: "001.jpg", type: "image/jpeg" }, 20), undefined);
    assert.equal(comicPageIndex(null, 20), undefined);
});
