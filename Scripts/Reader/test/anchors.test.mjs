// Text anchors keep the reader's place when the layout changes.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import playwright from "playwright";

const script = await readFile(new URL("../../../Sources/ChekReaderNavigator/Resources/reader.js", import.meta.url), "utf8");
const engine = playwright[process.env.READER_BROWSER ?? "webkit"];
let browser;

before(async () => {
    browser = await engine.launch();
});

after(async () => {
    await browser?.close();
});

const options = { layout: "reflowable", columns: 1, margin: 20, verticalMargin: 30, generation: 1 };

/** Each paragraph's words are unique, so an anchor matches one place only. */
async function open({ dir = "ltr" } = {}) {
    const page = await browser.newPage({ viewport: { width: 400, height: 600 } });
    const paragraphs = Array.from({ length: 50 }, (_, p) =>
        `<p>${Array.from({ length: 60 }, (_, w) => `w${p}x${w}`).join(" ")}</p>`).join("\n");
    await page.setContent(`<html dir="${dir}"><head></head><body>${paragraphs}</body></html>`);
    await page.addScriptTag({ content: script });
    await page.evaluate((options) => chekReader.paginate(options), options);
    return page;
}

/** Whether the first word of `text` is on screen. */
function wordVisible(page, text) {
    return page.evaluate((word) => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const index = node.nodeValue.indexOf(word);
            if (index >= 0) {
                const range = document.createRange();
                range.setStart(node, index);
                range.setEnd(node, index + word.length);
                const rect = range.getBoundingClientRect();
                return rect.right > 0 && rect.left < innerWidth;
            }
        }
        return false;
    }, text.trim().split(" ")[0]);
}

for (const dir of ["ltr", "rtl"]) {
    test(`finds the text at the start of a ${dir} page and returns to it`, async () => {
        const page = await open({ dir });
        await page.evaluate(() => chekReader.goToPage(5, 2));
        const anchor = await page.evaluate(() => chekReader.locate());
        assert.ok(anchor?.highlight.length > 0);
        assert.ok(anchor.before.length > 0);
        assert.ok(await wordVisible(page, anchor.highlight));

        await page.evaluate(() => chekReader.goToPage(0, 3));
        const state = await page.evaluate(({ highlight, before }) => chekReader.goToText(highlight, before, 4), anchor);
        assert.equal(state.page, 5);
        assert.equal(await page.evaluate(() => chekReader.goToText("not in the book", "", 5)), null);
        await page.close();
    });
}

test("keeps the same text on screen when the font size changes", async () => {
    const page = await open();
    await page.evaluate(() => chekReader.goToPage(7, 2));
    const anchor = await page.evaluate(() => chekReader.locate());
    const before = await page.evaluate(() => chekReader.state());

    const larger = await page.evaluate(() => chekReader.setPreferences({ fontScale: 1.6, theme: "sepia" }, 3));
    assert.ok(larger.pageCount > before.pageCount, `${larger.pageCount} pages at 160%, ${before.pageCount} before`);
    assert.ok(await wordVisible(page, anchor.highlight), "the anchor is still on screen");

    const background = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    assert.equal(background, "rgb(245, 236, 217)");

    const restored = await page.evaluate(() => chekReader.setPreferences({ fontScale: 1, theme: "default" }, 4));
    assert.equal(restored.pageCount, before.pageCount);
    assert.ok(await wordVisible(page, anchor.highlight));
    await page.close();
});
