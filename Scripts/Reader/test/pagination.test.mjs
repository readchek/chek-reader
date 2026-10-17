// Runs the compiled reader script in a real browser engine and checks the
// page math. CI runs it in WebKit, the engine the reader ships on, and in
// Chromium; set READER_BROWSER to pick one locally.
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

/** A page holding `count` paragraphs, each with an id, and the reader script. */
async function open({ count = 60, dir = "ltr", width = 400, height = 600 } = {}) {
    const page = await browser.newPage({ viewport: { width, height } });
    const paragraphs = Array.from({ length: count }, (_, index) =>
        `<p id="p${index}">Paragraph ${index}. ${"Lorem ipsum dolor sit amet. ".repeat(12)}</p>`).join("");
    await page.setContent(`<html dir="${dir}"><head></head><body>${paragraphs}</body></html>`);
    await page.addScriptTag({ content: script });
    return page;
}

const options = { layout: "reflowable", columns: 1, margin: 20, verticalMargin: 30, generation: 1 };

/** Whether the element with `id` is at least partly on screen. */
function visible(page, id) {
    return page.evaluate((id) => {
        const rect = document.getElementById(id).getBoundingClientRect();
        return rect.right > 0 && rect.left < innerWidth;
    }, id);
}

for (const dir of ["ltr", "rtl"]) {
    test(`paginates ${dir} text into whole screens`, async () => {
        const page = await open({ dir });
        const state = await page.evaluate((options) => chekReader.paginate(options), options);
        assert.equal(state.page, 0);
        assert.ok(state.pageCount > 5, `expected several pages, got ${state.pageCount}`);
        assert.ok(await visible(page, "p0"));

        const turned = await page.evaluate(() => chekReader.goToPage(3, 2));
        assert.equal(turned.page, 3);
        assert.equal(turned.generation, 2);
        const offset = await page.evaluate(() => document.scrollingElement.scrollLeft);
        assert.equal(Math.abs(offset), 3 * 400);

        const last = await page.evaluate(() => chekReader.goToLastPage(3));
        assert.equal(last.page, state.pageCount - 1);
        assert.ok(await visible(page, "p59"), "the last page shows the end of the text");

        const past = await page.evaluate(() => chekReader.goToPage(1000, 4));
        assert.equal(past.page, state.pageCount - 1);
        await page.close();
    });

    test(`finds the page holding a fragment in ${dir} text`, async () => {
        const page = await open({ dir });
        await page.evaluate((options) => chekReader.paginate(options), options);
        const state = await page.evaluate(() => chekReader.goToFragment("p40", 2));
        assert.ok(state.page > 0);
        assert.ok(await visible(page, "p40"));
        assert.equal(await page.evaluate(() => chekReader.goToFragment("missing", 3)), null);
        await page.close();
    });
}

test("keeps the reading position when the viewport changes", async () => {
    const page = await open();
    await page.evaluate((options) => chekReader.paginate(options), options);
    const before = await page.evaluate(() => chekReader.goToProgression(0.5, 2));
    await page.setViewportSize({ width: 600, height: 600 });
    await page.waitForFunction((count) => chekReader.state().pageCount !== count, before.pageCount);
    const after = await page.evaluate(() => chekReader.state());
    assert.ok(Math.abs(after.progression - before.progression) < 1 / after.pageCount + 1e-9);
    await page.close();
});

test("uses two columns on a wide screen when asked to choose", async () => {
    const page = await open({ width: 1200, height: 800 });
    const auto = await page.evaluate((options) => chekReader.paginate({ ...options, columns: 0 }), options);
    const columns = await page.evaluate(() => getComputedStyle(document.documentElement).columnCount);
    assert.equal(columns, "2");
    assert.ok(auto.pageCount >= 1);
    await page.close();
});

test("fits a fixed-layout page to the screen", async () => {
    const page = await browser.newPage({ viewport: { width: 400, height: 600 } });
    await page.setContent(`<html><head><meta name="viewport" content="width=800, height=1000"></head>
        <body><div style="width:800px;height:1000px"></div></body></html>`);
    await page.addScriptTag({ content: script });
    const state = await page.evaluate((options) => chekReader.paginate({ ...options, layout: "fixed" }), options);
    assert.equal(state.pageCount, 1);
    const box = await page.evaluate(() => document.documentElement.getBoundingClientRect().toJSON());
    assert.ok(Math.abs(box.width - 400) < 1, `scaled width ${box.width}`);
    assert.ok(Math.abs(box.height - 500) < 1, `scaled height ${box.height}`);
    await page.close();
});
