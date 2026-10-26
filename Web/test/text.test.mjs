import assert from "node:assert/strict";
import { test } from "node:test";
import { makeSlugs, markdownHtml } from "../dist/markdown.js";
import { TextBook } from "../dist/text.js";

// These follow the Swift package's PlainTextTests and MarkdownTests, so the
// two convert a file to the same documents.

const blob = (text) => new Blob([text]);
const text = async (book, index) => (await book.resource(book.readingOrder[index].href)).text();

test("plain text splits at chapter headings", async () => {
    const book = await TextBook.plainText(blob([
        "Title: The Lighthouse",
        "Author: Ada Writer",
        "",
        "CHAPTER I",
        "",
        "The keeper climbed",
        "the stairs.",
        "",
        "It was late & dark.",
        "",
        "CHAPTER II",
        "",
        "Morning <came>.",
    ].join("\n")), "book.txt");
    assert.equal(book.metadata.title, "The Lighthouse");
    assert.deepEqual(book.metadata.authors, ["Ada Writer"]);
    assert.equal(book.readingOrder.length, 3);
    assert.deepEqual(book.toc.map((item) => item.title), ["CHAPTER I", "CHAPTER II"]);
    assert.deepEqual(book.toc.map((item) => item.href), ["text/part-0002.xhtml", "text/part-0003.xhtml"]);
    const chapter = await text(book, 1);
    assert.ok(chapter.includes('<h2 id="chapter">CHAPTER I</h2>'));
    assert.ok(chapter.includes('<p class="plain">The keeper climbed the stairs.</p>'));
    assert.ok(chapter.includes("It was late &amp; dark."));
    assert.ok((await text(book, 2)).includes("Morning &lt;came&gt;."));
});

test("long plain text without headings is split into parts", async () => {
    const paragraph = "word ".repeat(2000);
    const book = await TextBook.plainText(blob(Array(12).fill(paragraph).join("\n\n")), "Long_Story.txt");
    assert.equal(book.readingOrder.length, 2);
    assert.deepEqual(book.toc, []);
    assert.equal(book.metadata.title, "Long Story");
});

test("plain text decodes UTF-16 and Windows-1252", async () => {
    const utf16 = await TextBook.plainText(new Blob([new Uint8Array([0xff, 0xfe]), Buffer.from("Café", "utf16le")]));
    assert.ok((await text(utf16, 0)).includes("Café"));
    const cp1252 = await TextBook.plainText(new Blob([new Uint8Array([0x43, 0x61, 0x66, 0xe9, 0x20, 0x93, 0x71, 0x94])]));
    assert.ok((await text(cp1252, 0)).includes("Café “q”"));
});

test("plain text drops characters XML doesn't allow", async () => {
    const book = await TextBook.plainText(blob("CHAPTER 1\n\nA \u0001 b\n\nCHAPTER 2\n\n<&>"));
    assert.ok(!(await text(book, 0)).includes("\u0001"));
    assert.ok((await text(book, 1)).includes("&lt;&amp;&gt;"));
});

test("a document's bytes match the Swift package's, so positions do", async () => {
    const book = await TextBook.plainText(blob("Hello"), "a.txt");
    assert.equal(await text(book, 0), `<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><meta charset="utf-8"/><title>a</title><link rel="stylesheet" type="text/css" href="../styles/text.css"/></head>
<body>
<p class="plain">Hello</p>

</body>
</html>
`);
    assert.equal(book.readingOrder[0].positions, 1);
    assert.ok(book.has("styles/text.css"));
});

test("Markdown splits at headings, with front matter", async () => {
    const book = await TextBook.markdown(blob(`---
title: "Field Notes"
author: Ada Writer
lang: en
---
Intro text.

# First

See [the second](#second-part).

## Detail

# Second Part

Back to [first](#first).`), "notes.md");
    assert.equal(book.metadata.title, "Field Notes");
    assert.deepEqual(book.metadata.authors, ["Ada Writer"]);
    assert.equal(book.metadata.language, "en");
    assert.deepEqual(book.readingOrder.map((item) => item.href), ["text/chapter-0001.xhtml", "text/chapter-0002.xhtml", "text/chapter-0003.xhtml"]);
    assert.deepEqual(book.toc.map((item) => item.title), ["First", "Second Part"]);
    assert.deepEqual(book.toc.map((item) => item.href), ["text/chapter-0002.xhtml#first", "text/chapter-0003.xhtml#second-part"]);
    assert.deepEqual(book.toc[0].children.map((item) => item.href), ["text/chapter-0002.xhtml#detail"]);
    const first = await text(book, 1);
    assert.ok(first.includes('<a href="chapter-0003.xhtml#second-part">the second</a>'));
    assert.ok(first.includes('<h1 id="first">First</h1>'));
});

test("a Markdown title falls back to the first heading", async () => {
    assert.equal((await TextBook.markdown(blob("# The **Title**\n\nText"), "notes.md")).metadata.title, "The Title");
});

test("Markdown inline syntax", () => {
    assert.equal(markdownHtml("Some *em*, **strong**, `a < b`, ~~gone~~ and snake_case_name."),
        "<p>Some <em>em</em>, <strong>strong</strong>, <code>a &lt; b</code>, <del>gone</del> and snake_case_name.</p>");
    assert.equal(markdownHtml('A [link](https://example.com "Title") and <https://chek.app>.'),
        '<p>A <a href="https://example.com" title="Title">link</a> and <a href="https://chek.app">https://chek.app</a>.</p>');
    assert.equal(markdownHtml("![A lighthouse](light.png)"), '<p><span class="image">A lighthouse</span></p>');
    assert.equal(markdownHtml("Fish &amp; chips&nbsp;&copy; &#169; &bogus; \\*not em\\*"),
        "<p>Fish &amp; chips © © &amp;bogus; *not em*</p>");
    assert.equal(markdownHtml("line one  \nline two"), "<p>line one<br/>\nline two</p>");
    assert.equal(markdownHtml("**unclosed"), "<p>**unclosed</p>");
});

test("Markdown blocks", () => {
    assert.equal(markdownHtml("Title\n=====\n\nSub\n---"), "<h1>Title</h1>\n<h2>Sub</h2>");
    assert.equal(markdownHtml("```swift\nlet a = 1 < 2\n```"), '<pre><code class="language-swift">let a = 1 &lt; 2</code></pre>');
    assert.equal(markdownHtml("    indented\n    code"), "<pre><code>indented\ncode</code></pre>");
    assert.equal(markdownHtml("> quoted\nlazy"), "<blockquote>\n<p>quoted\nlazy</p>\n</blockquote>");
    assert.equal(markdownHtml("- one\n- two\n  - nested"), "<ul>\n<li>one</li>\n<li>two\n<ul>\n<li>nested</li>\n</ul></li>\n</ul>");
    assert.equal(markdownHtml("3. three\n4. four"), '<ol start="3">\n<li>three</li>\n<li>four</li>\n</ol>');
    assert.equal(markdownHtml("- a\n\n- b"), "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>");
    assert.equal(markdownHtml("***"), "<hr/>");
    assert.equal(markdownHtml("| a | b |\n|:--|--:|\n| 1 | 2 |"),
        '<table>\n<thead><tr><th style="text-align: left">a</th><th style="text-align: right">b</th></tr></thead>\n<tbody>\n<tr><td style="text-align: left">1</td><td style="text-align: right">2</td></tr>\n</tbody>\n</table>');
});

test("Markdown's raw HTML keeps only its text", () => {
    assert.equal(markdownHtml('<div align="center">\n<script>alert(1)</script> Hello <!-- note -->\n</div>'), "<p>alert(1) Hello</p>");
});

test("deep Markdown nesting stays bounded", () => {
    assert.equal(markdownHtml("> ".repeat(200) + "deep").split("<blockquote>").length - 1, 32);
});

test("heading ids are unique", () => {
    const slugs = makeSlugs();
    assert.equal(slugs.make("Hello, World!"), "hello-world");
    assert.equal(slugs.make("Hello World"), "hello-world-1");
    assert.equal(slugs.make("2024"), "section-2024");
});
