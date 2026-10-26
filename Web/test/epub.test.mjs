import assert from "node:assert/strict";
import { test } from "node:test";
import { crc32, deflateRawSync } from "node:zlib";
import { resolveHref } from "../dist/href.js";
import { rewriteCss } from "../dist/prepare.js";
import { ZipArchive, ZipError } from "../dist/zip.js";

test("hrefs resolve from their document to paths from the root", () => {
    assert.equal(resolveHref("chapter-2.xhtml", "epub/text/chapter-1.xhtml"), "epub/text/chapter-2.xhtml");
    assert.equal(resolveHref("../images/a%20b.png", "epub/text/chapter-1.xhtml"), "epub/images/a b.png");
    assert.equal(resolveHref("#note-3", "epub/text/notes.xhtml"), "epub/text/notes.xhtml#note-3");
    assert.equal(resolveHref("/cover.xhtml?x=1", "epub/text/a.xhtml"), "cover.xhtml");
});

test("hrefs outside the publication resolve to nothing", () => {
    assert.equal(resolveHref("https://example.com/", "a.xhtml"), null);
    assert.equal(resolveHref("../../secret", "epub/a.xhtml"), null);
});

test("CSS references are rewritten, and data URLs are left alone", () => {
    const css = `@import "base.css"; a { background: url( 'img/x.png' ) } b { src: url(data:font/woff2;base64,AA) }`;
    const rewritten = rewriteCss(css, (href) => (href === "base.css" ? "chek:base" : href.startsWith("img/") ? "chek:x" : null));
    assert.equal(rewritten, `@import "chek:base"; a { background: url("chek:x") } b { src: url(data:font/woff2;base64,AA) }`);
    assert.equal(rewriteCss("a { b: url(../../out.png) }", () => null), `a { b: url("about:invalid") }`);
});

// A ZIP built here, one stored entry and one deflated, as EPUBs have.
function zip(files) {
    const locals = [];
    const centrals = [];
    let offset = 0;
    for (const [name, text, deflate] of files) {
        const nameBytes = Buffer.from(name);
        const data = Buffer.from(text);
        const stored = deflate ? deflateRawSync(data) : data;
        const local = Buffer.alloc(30);
        local.writeUInt32LE(0x04034b50, 0);
        local.writeUInt16LE(20, 4);
        local.writeUInt16LE(deflate ? 8 : 0, 8);
        local.writeUInt32LE(crc32(data), 14);
        local.writeUInt32LE(stored.length, 18);
        local.writeUInt32LE(data.length, 22);
        local.writeUInt16LE(nameBytes.length, 26);
        const central = Buffer.alloc(46);
        central.writeUInt32LE(0x02014b50, 0);
        central.writeUInt16LE(20, 4);
        central.writeUInt16LE(20, 6);
        central.writeUInt16LE(deflate ? 8 : 0, 10);
        central.writeUInt32LE(crc32(data), 16);
        central.writeUInt32LE(stored.length, 20);
        central.writeUInt32LE(data.length, 24);
        central.writeUInt16LE(nameBytes.length, 28);
        central.writeUInt32LE(offset, 42);
        locals.push(local, nameBytes, stored);
        centrals.push(central, nameBytes);
        offset += local.length + nameBytes.length + stored.length;
    }
    const directory = Buffer.concat(centrals);
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(files.length, 8);
    end.writeUInt16LE(files.length, 10);
    end.writeUInt32LE(directory.length, 12);
    end.writeUInt32LE(offset, 16);
    return new Blob([...locals, directory, end]);
}

test("a ZIP's stored and deflated entries read back", async () => {
    const archive = await ZipArchive.open(zip([
        ["mimetype", "application/epub+zip", false],
        ["OEBPS/content.opf", "<package>".repeat(50), true],
    ]));
    assert.deepEqual(archive.paths.sort(), ["OEBPS/content.opf", "mimetype"]);
    assert.equal(await archive.text("mimetype"), "application/epub+zip");
    assert.equal(await archive.text("OEBPS/content.opf"), "<package>".repeat(50));
});

test("a ZIP over the limits is refused", async () => {
    const files = [["a", "1", false], ["b", "2", false]];
    await assert.rejects(ZipArchive.open(zip(files), { entries: 1, entrySize: 100 }), ZipError);
    const archive = await ZipArchive.open(zip([["big", "x".repeat(200), true]]), { entries: 10, entrySize: 100 });
    await assert.rejects(archive.text("big"), ZipError);
    await assert.rejects(ZipArchive.open(new Blob(["not a zip"])), ZipError);
});
