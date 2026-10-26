// Plain text and Markdown, converted to XHTML when they open so they read
// in the book view like EPUB, with the same text size, themes and page
// turns. The conversion matches the Swift package's TextModule document
// for document, so resource paths and positions, and so locators, are the
// same on every platform.
import { renderMarkdown } from "./markdown.js";
const xhtmlType = "application/xhtml+xml";
const stylesPath = "styles/text.css";
// Sets only what plain text and Markdown can't, so the reader's themes and
// text size still apply.
const styles = `body { line-height: 1.5; }
h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; }
code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
blockquote { margin-inline: 1.5em 0; padding-inline-start: 1em; border-inline-start: 3px solid rgba(128, 128, 128, 0.5); }
table { border-collapse: collapse; }
th, td { border: 1px solid rgba(128, 128, 128, 0.5); padding: 0.25em 0.5em; }
img { max-width: 100%; height: auto; }
hr { border: none; border-top: 1px solid rgba(128, 128, 128, 0.5); }
p.plain { margin: 0 0 0.75em; }
`;
/** The characters in a part, when plain text has no chapter headings. */
const partLength = 50_000;
/** Plain text or Markdown, opened as a publication of XHTML documents. */
export class TextBook {
    metadata;
    toc;
    resources = new Map();
    readingOrder;
    constructor(metadata, documents, toc) {
        this.metadata = metadata;
        this.toc = toc;
        const encoder = new TextEncoder();
        this.resources.set(stylesPath, new Blob([styles], { type: "text/css" }));
        this.readingOrder = documents.map(({ href, xhtml }) => {
            const bytes = encoder.encode(xhtml);
            this.resources.set(href, new Blob([bytes], { type: xhtmlType }));
            return { href, type: xhtmlType, fixed: false, positions: Math.max(1, Math.ceil(bytes.length / 1024)) };
        });
    }
    /**
     * Opens plain text. Headings such as "Chapter 12" or "PART TWO" split it
     * into chapters and make the contents. Text can be UTF-8, UTF-16 with a
     * byte order mark, or Windows-1252.
     */
    static async plainText(file, fileName) {
        const { metadata, documents, toc } = convertPlainText(decodeText(await file.arrayBuffer()), fileName);
        return new TextBook(metadata, documents, toc);
    }
    /**
     * Opens Markdown, with a chapter per top-level heading and metadata from
     * YAML front matter. Raw HTML is reduced to its text, and images show
     * their description, since the file is read on its own.
     */
    static async markdown(file, fileName) {
        const { metadata, documents, toc } = renderMarkdown(decodeText(await file.arrayBuffer()), fileName);
        return new TextBook(metadata, documents, toc);
    }
    async resource(path) {
        const blob = this.resources.get(path);
        if (!blob) {
            throw new Error(`The book has no resource at ${path}.`);
        }
        return blob;
    }
    has(path) {
        return this.resources.has(path);
    }
    typeOf(path) {
        return this.resources.get(path)?.type ?? "application/octet-stream";
    }
    indexOf(path) {
        return this.readingOrder.findIndex((item) => item.href === path);
    }
    get positionCount() {
        return this.readingOrder.reduce((sum, item) => sum + item.positions, 0);
    }
}
/**
 * The text in `bytes`: by its byte order mark when it has one, else as
 * UTF-8, else as Windows-1252, the usual encoding of older text files.
 * Line endings become `\n`.
 */
export function decodeText(bytes) {
    const view = new Uint8Array(bytes);
    let text;
    if (view[0] === 0xef && view[1] === 0xbb && view[2] === 0xbf) {
        text = new TextDecoder("utf-8").decode(view.subarray(3));
    }
    else if (view[0] === 0xff && view[1] === 0xfe) {
        text = new TextDecoder("utf-16le").decode(view.subarray(2));
    }
    else if (view[0] === 0xfe && view[1] === 0xff) {
        text = new TextDecoder("utf-16be").decode(view.subarray(2));
    }
    else {
        try {
            text = new TextDecoder("utf-8", { fatal: true }).decode(view);
        }
        catch {
            text = decodeWindows1252(view);
        }
    }
    return text.replace(/\r\n?/g, "\n");
}
// Windows-1252 is Latin-1 but for 0x80 to 0x9F. Decoded here, since not
// every runtime's TextDecoder knows it.
const windows1252High = "€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F\u0090‘’“”•–—˜™š›œ\u009DžŸ";
function decodeWindows1252(bytes) {
    let text = "";
    for (let start = 0; start < bytes.length; start += 8192) {
        const chunk = Array.from(bytes.subarray(start, start + 8192), (byte) => byte >= 0x80 && byte <= 0x9f ? windows1252High[byte - 0x80] : String.fromCharCode(byte));
        text += chunk.join("");
    }
    return text;
}
/** A title made from a file name: without its extension, and with underscores as spaces. */
export function titleFromFileName(fileName) {
    if (!fileName) {
        return undefined;
    }
    const dot = fileName.lastIndexOf(".");
    const title = (dot > 0 ? fileName.slice(0, dot) : fileName).replace(/_/g, " ").trim();
    return title || undefined;
}
/** Escapes text for XHTML, dropping control characters XML doesn't allow. */
export function escapeXhtml(text) {
    return text
        .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g, "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}
/** A complete XHTML document around `body`, byte for byte as the Swift package's XHTML.document. */
export function xhtmlDocument(title, language, body) {
    const head = `<meta charset="utf-8"/><title>${escapeXhtml(title ?? "")}</title>`
        + `<link rel="stylesheet" type="text/css" href="../${stylesPath}"/>`;
    const lang = language ? ` lang="${escapeXhtml(language)}" xml:lang="${escapeXhtml(language)}"` : "";
    return `<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"${lang}>
<head>${head}</head>
<body>
${body}
</body>
</html>
`;
}
/** The number of characters as Swift counts them, by grapheme cluster. */
export function characterCount(text) {
    // eslint-disable-next-line no-control-regex
    if (/^[\x00-\x7f]*$/.test(text)) {
        return text.length;
    }
    let count = 0;
    for (const _ of segmenter().segment(text)) {
        count += 1;
    }
    return count;
}
let graphemes;
function segmenter() {
    graphemes ??= new Intl.Segmenter(undefined, { granularity: "grapheme" });
    return graphemes;
}
export function partHref(prefix, index) {
    return `text/${prefix}-${String(index + 1).padStart(4, "0")}.xhtml`;
}
function convertPlainText(text, fileName) {
    const lines = text.split("\n");
    const paragraphs = plainParagraphs(lines);
    const metadata = gutenbergMetadata(lines.slice(0, 200));
    metadata.title ||= titleFromFileName(fileName) ?? "";
    // Each chapter: its heading, if it has one, and its paragraphs.
    const chapters = [];
    const headings = paragraphs.flatMap((paragraph, index) => (isPlainHeading(paragraph) ? [index] : []));
    if (headings.length >= 2) {
        const headingSet = new Set(headings);
        // Text before the first heading, such as a title page, is a chapter of its own.
        const starts = [...(headings[0] > 0 ? [0] : []), ...headings];
        starts.forEach((start, offset) => {
            const end = starts[offset + 1] ?? paragraphs.length;
            const heading = headingSet.has(start);
            chapters.push({
                title: heading ? paragraphs[start] : undefined,
                paragraphs: paragraphs.slice(heading ? start + 1 : start, end),
            });
        });
    }
    else {
        let part = [];
        let length = 0;
        for (const paragraph of paragraphs) {
            part.push(paragraph);
            length += characterCount(paragraph);
            if (length >= partLength) {
                chapters.push({ paragraphs: part });
                part = [];
                length = 0;
            }
        }
        if (part.length > 0 || chapters.length === 0) {
            chapters.push({ paragraphs: part });
        }
    }
    const toc = [];
    const documents = chapters.map((chapter, index) => {
        const href = partHref("part", index);
        let body = "";
        if (chapter.title !== undefined) {
            body += `<h2 id="chapter">${escapeXhtml(chapter.title)}</h2>\n`;
            toc.push({ title: chapter.title, href, children: [] });
        }
        for (const paragraph of chapter.paragraphs) {
            body += `<p class="plain">${escapeXhtml(paragraph).replace(/\n/g, "<br/>\n")}</p>\n`;
        }
        return { href, xhtml: xhtmlDocument(chapter.title ?? (metadata.title || undefined), undefined, body) };
    });
    return { metadata, documents, toc };
}
/**
 * The text's paragraphs. Text with blank lines between paragraphs is
 * usually wrapped at a fixed width, so its lines are joined into flowing
 * paragraphs. Text without blank lines has a paragraph per line.
 */
function plainParagraphs(lines) {
    const blank = lines.filter((line) => /^\s*$/.test(line)).length;
    const separatedByBlankLines = blank * 10 >= lines.length;
    const paragraphs = [];
    let current = [];
    const flush = () => {
        if (current.length > 0) {
            paragraphs.push(current.join(" "));
            current = [];
        }
    };
    for (const line of lines) {
        const trimmed = trimSpaces(line);
        if (trimmed === "") {
            flush();
        }
        else if (separatedByBlankLines) {
            current.push(trimmed);
        }
        else {
            paragraphs.push(trimmed);
        }
    }
    flush();
    return paragraphs;
}
const headingWords = new Set(["chapter", "part", "book", "prologue", "epilogue", "preface", "introduction", "volume", "act"]);
/** Whether a paragraph looks like a chapter heading: short, on its own, and starting with a word such as "Chapter" or a Roman numeral. */
function isPlainHeading(paragraph) {
    if (characterCount(paragraph) > 80 || paragraph.includes("\n")) {
        return false;
    }
    const words = paragraph.split(/[ .:]/).filter(Boolean);
    const first = words[0]?.toLowerCase();
    if (!first) {
        return false;
    }
    if (headingWords.has(first)) {
        return words.length <= 12;
    }
    // A Roman numeral alone, as some novels number their chapters.
    return words.length === 1 && first.length <= 7 && /^[ivxlc]+$/.test(first);
}
/** Project Gutenberg's header fields. */
function gutenbergMetadata(lines) {
    const metadata = { title: "", authors: [], language: null, readingProgression: "ltr" };
    const field = (name, line) => {
        if (!line.startsWith(`${name}:`)) {
            return undefined;
        }
        return trimSpaces(line.slice(name.length + 1)) || undefined;
    };
    for (const line of lines) {
        let value;
        if ((value = field("Title", line))) {
            metadata.title ||= value;
        }
        else if ((value = field("Author", line))) {
            if (metadata.authors.length === 0) {
                metadata.authors = [value];
            }
        }
        else if ((value = field("Language", line)) && metadata.language === null) {
            metadata.language = value === "English" ? "en" : value;
        }
    }
    return metadata;
}
/** Trims spaces and tabs, as Swift's `.whitespaces` does, leaving line breaks. */
export function trimSpaces(text) {
    return text.replace(/^[^\S\n]+|[^\S\n]+$/g, "");
}
