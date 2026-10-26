// Markdown to XHTML, ported from the Swift package's Markdown parser so a
// document converts to the same chapters, ids and positions everywhere.
// It follows CommonMark and the GitHub table extension closely enough for
// real documents. Raw HTML isn't passed through: an HTML block keeps only
// its text, so a document can't add scripts or markup the reader didn't
// expect.

import type { BookMetadata, TocItem } from "./publication.js";
import { type TextDocument, escapeXhtml, partHref, titleFromFileName, trimSpaces, xhtmlDocument } from "./text.js";

type Alignment = "left" | "center" | "right" | null;

type Block =
    | { kind: "heading"; level: number; text: string; id?: string }
    | { kind: "paragraph"; text: string }
    | { kind: "code"; language: string | undefined; text: string }
    | { kind: "quote"; blocks: Block[] }
    | { kind: "list"; ordered: boolean; start: number; items: Block[][]; tight: boolean }
    | { kind: "table"; header: string[]; alignments: Alignment[]; rows: string[][] }
    | { kind: "rule" };

/** Converts a Markdown file into chapters, contents and metadata. */
export function renderMarkdown(
    text: string,
    fileName: string | undefined,
): { metadata: BookMetadata; documents: TextDocument[]; toc: TocItem[] } {
    let body = text;
    const metadata: BookMetadata = { title: "", authors: [], language: null, readingProgression: "ltr" };
    const front = frontMatter(text);
    if (front) {
        body = front.body;
        metadata.title = front.fields.get("title") ?? "";
        const author = front.fields.get("author");
        if (author) {
            metadata.authors = [author];
        }
        metadata.language = front.fields.get("lang") ?? front.fields.get("language") ?? null;
    }

    const blocks = parseBlocks(body.split("\n"), 0);

    // Chapters start at the shallowest heading level that's used more than
    // once, so a document with one title and several sections is split at
    // the sections.
    const levels = blocks.flatMap((block) => (block.kind === "heading" ? [block.level] : []));
    const lowest = levels.length > 0 ? Math.min(...levels) : undefined;
    const splitLevel = [1, 2, 3].find((level) => levels.filter((l) => l === level).length > 1) ?? lowest ?? 0;

    // Give headings ids and decide which chapter each block goes in.
    const slugs = new Slugs();
    const chapters: Block[][] = [[]];
    const headings: { level: number; text: string; chapter: number; id: string }[] = [];
    for (const block of blocks) {
        if (block.kind === "heading") {
            block.id = slugs.make(block.text);
            if (block.level <= splitLevel && chapters[chapters.length - 1]!.length > 0) {
                chapters.push([]);
            }
            headings.push({ level: block.level, text: block.text, chapter: chapters.length - 1, id: block.id });
        }
        chapters[chapters.length - 1]!.push(block);
    }

    if (!metadata.title) {
        const first = headings.find((heading) => heading.level === lowest);
        metadata.title = (first ? plain(first.text) : titleFromFileName(fileName)) ?? "";
    }

    const hrefs = chapters.map((_, index) => partHref("chapter", index));
    const chapterOfId = new Map<string, number>();
    for (const heading of headings) {
        if (!chapterOfId.has(heading.id)) {
            chapterOfId.set(heading.id, heading.chapter);
        }
    }
    const documents = chapters.map((chapter, index) => {
        const inline = new Inline((destination) => {
            if (!destination.startsWith("#")) {
                return destination;
            }
            const id = destination.slice(1);
            const target = chapterOfId.get(id);
            if (target === undefined) {
                return null;
            }
            return target === index ? destination : `${hrefs[target]!.slice(5)}#${id}`;
        });
        const heading = headings.find((h) => h.chapter === index);
        const title = heading ? plain(heading.text) : metadata.title || undefined;
        const html = renderBlocks(chapter, inline);
        return { href: hrefs[index]!, xhtml: xhtmlDocument(title, metadata.language ?? undefined, html) };
    });

    const toc = nest(
        headings
            .filter((heading) => heading.level <= Math.max(splitLevel, 1) + 1)
            .map((heading) => ({
                level: heading.level,
                item: { title: plain(heading.text), href: `${hrefs[heading.chapter]}#${heading.id}`, children: [] },
            })),
    );
    return { metadata, documents, toc };
}

/** Nests entries under the nearest shallower entry before them. */
function nest(entries: { level: number; item: TocItem }[]): TocItem[] {
    let index = 0;
    const children = (deeperThan: number): TocItem[] => {
        const items: TocItem[] = [];
        while (index < entries.length && entries[index]!.level > deeperThan) {
            const { level, item } = entries[index]!;
            index += 1;
            item.children = children(level);
            items.push(item);
        }
        return items;
    };
    return children(0);
}

/** A heading's text without its Markdown, for titles. */
export function plain(text: string): string {
    let result = "";
    let skipping = false;
    for (const character of text) {
        if ("*_`~".includes(character)) {
            continue;
        } else if (character === "]") {
            skipping = true;
        } else if (character === "(" && skipping) {
            continue;
        } else if (character === ")" && skipping) {
            skipping = false;
        } else if (character === "[") {
            continue;
        } else if (!skipping || character === " ") {
            result += character;
        }
    }
    return trimSpaces(result);
}

/** YAML front matter between `---` lines at the very start. Only simple `key: value` lines are read. */
function frontMatter(text: string): { fields: Map<string, string>; body: string } | undefined {
    if (!text.startsWith("---\n")) {
        return undefined;
    }
    const lines = text.split("\n");
    const end = lines.findIndex((line, index) => index > 0 && (line === "---" || line === "..."));
    if (end < 0) {
        return undefined;
    }
    const fields = new Map<string, string>();
    for (const line of lines.slice(1, end)) {
        const colon = line.indexOf(":");
        if (colon < 0) {
            continue;
        }
        const key = trimSpaces(line.slice(0, colon)).toLowerCase();
        let value = trimSpaces(line.slice(colon + 1));
        const quote = value[0];
        if (value.length >= 2 && (quote === '"' || quote === "'") && value.endsWith(quote)) {
            value = value.slice(1, -1);
        }
        if (key && value) {
            fields.set(key, value);
        }
    }
    return { fields, body: lines.slice(end + 1).join("\n") };
}

/** Makes unique, URL-friendly ids from heading text, as GitHub does. */
class Slugs {
    private readonly used = new Map<string, number>();

    make(text: string): string {
        let slug = "";
        for (const character of plain(text).toLowerCase()) {
            if (/[\p{L}\p{N}_-]/u.test(character)) {
                slug += character;
            } else if (character === " ") {
                slug += "-";
            }
        }
        if (slug === "" || /^\p{N}/u.test(slug)) {
            slug = `section-${slug}`;
        }
        const count = this.used.get(slug);
        if (count !== undefined) {
            this.used.set(slug, count + 1);
            return `${slug}-${count}`;
        }
        this.used.set(slug, 1);
        return slug;
    }
}

// MARK: Blocks

/** Containers nested deeper than this are read as plain paragraphs, so a hostile document can't recurse without bound. */
const maxDepth = 32;

function parseBlocks(lines: string[], depth: number): Block[] {
    const blocks: Block[] = [];
    let index = 0;
    while (index < lines.length) {
        const line = lines[index]!;
        if (isBlank(line)) {
            index += 1;
            continue;
        }
        const indent = indentation(line);
        const content = stripIndentation(line, 3);

        // Indented code.
        if (indent >= 4) {
            const code: string[] = [];
            while (index < lines.length && (isBlank(lines[index]!) || indentation(lines[index]!) >= 4)) {
                code.push(stripIndentation(lines[index]!, 4));
                index += 1;
            }
            while (code.length > 0 && isBlank(code[code.length - 1]!)) {
                code.pop();
            }
            blocks.push({ kind: "code", language: undefined, text: code.join("\n") });
            continue;
        }

        // Fenced code.
        const fenced = fence(content);
        if (fenced) {
            const code: string[] = [];
            index += 1;
            while (index < lines.length) {
                const candidate = stripIndentation(lines[index]!, 3);
                if (
                    candidate.startsWith(fenced.character.repeat(fenced.length))
                    && [...candidate].every((c) => c === fenced.character || c === " " || c === "\t")
                ) {
                    index += 1;
                    break;
                }
                code.push(stripIndentation(lines[index]!, indent));
                index += 1;
            }
            blocks.push({ kind: "code", language: fenced.info, text: code.join("\n") });
            continue;
        }

        const heading = atxHeading(content);
        if (heading) {
            blocks.push({ kind: "heading", level: heading.level, text: heading.text });
            index += 1;
            continue;
        }

        if (isThematicBreak(content)) {
            blocks.push({ kind: "rule" });
            index += 1;
            continue;
        }

        if (content.startsWith(">")) {
            const quoted: string[] = [];
            while (index < lines.length && !isBlank(lines[index]!)) {
                const candidate = stripIndentation(lines[index]!, 3);
                if (candidate.startsWith(">")) {
                    let rest = candidate.slice(1);
                    if (rest.startsWith(" ")) {
                        rest = rest.slice(1);
                    }
                    quoted.push(rest);
                } else if (quoted.length > 0 && !isBlank(quoted[quoted.length - 1]!) && !startsBlock(candidate)) {
                    // A lazy continuation of the quoted paragraph.
                    quoted.push(candidate);
                } else {
                    break;
                }
                index += 1;
            }
            blocks.push(
                depth < maxDepth
                    ? { kind: "quote", blocks: parseBlocks(quoted, depth + 1) }
                    : { kind: "paragraph", text: quoted.join("\n") },
            );
            continue;
        }

        const marker = listMarker(content);
        if (marker) {
            const [list, next] = parseList(lines, index, marker, depth);
            blocks.push(list);
            index = next;
            continue;
        }

        if (index + 1 < lines.length && content.includes("|")) {
            const alignments = tableDelimiter(lines[index + 1]!);
            if (alignments) {
                const header = cells(content);
                if (header.length === alignments.length) {
                    const rows: string[][] = [];
                    index += 2;
                    while (index < lines.length && !isBlank(lines[index]!) && lines[index]!.includes("|")) {
                        const row = cells(stripIndentation(lines[index]!, 3)).slice(0, header.length);
                        while (row.length < header.length) {
                            row.push("");
                        }
                        rows.push(row);
                        index += 1;
                    }
                    blocks.push({ kind: "table", header, alignments, rows });
                    continue;
                }
            }
        }

        if (content.startsWith("<") && /^[\p{L}/!]/u.test(content.slice(1))) {
            const html: string[] = [];
            while (index < lines.length && !isBlank(lines[index]!)) {
                html.push(lines[index]!);
                index += 1;
            }
            const text = textOfHtml(html.join("\n"));
            if (text) {
                blocks.push({ kind: "paragraph", text });
            }
            continue;
        }

        // A paragraph, which a setext underline turns into a heading.
        let paragraph: string[] = [content];
        index += 1;
        while (index < lines.length && !isBlank(lines[index]!)) {
            const candidate = stripIndentation(lines[index]!, 3);
            const level = setextLevel(candidate);
            if (level) {
                blocks.push({ kind: "heading", level, text: trimSpaces(paragraph.join(" ")) });
                paragraph = [];
                index += 1;
                break;
            }
            if (indentation(lines[index]!) < 4 && startsBlock(candidate)) {
                break;
            }
            paragraph.push(candidate);
            index += 1;
        }
        if (paragraph.length > 0) {
            blocks.push({ kind: "paragraph", text: paragraph.join("\n") });
        }
    }
    return blocks;
}

interface ListMarker {
    ordered: boolean;
    start: number;
    /** `-`, `*`, `+`, `.` or `)`, which must match for items to share a list. */
    delimiter: string;
    /** The columns before the item's content: the marker and its spaces. */
    width: number;
}

function leadingSpaces(text: string): number {
    return /^ */.exec(text)![0].length;
}

function listMarker(content: string): ListMarker | undefined {
    const first = content[0];
    if (first === undefined) {
        return undefined;
    }
    if (first === "-" || first === "*" || first === "+") {
        const rest = content.slice(1);
        if (!(rest === "" || rest[0] === " " || rest[0] === "\t")) {
            return undefined;
        }
        const spaces = leadingSpaces(rest);
        return { ordered: false, start: 1, delimiter: first, width: 1 + (rest === "" || spaces > 4 ? 1 : spaces) };
    }
    const digits = /^[0-9]*/.exec(content)![0];
    if (digits.length < 1 || digits.length > 9) {
        return undefined;
    }
    const rest = content.slice(digits.length);
    const delimiter = rest[0];
    if (delimiter !== "." && delimiter !== ")") {
        return undefined;
    }
    const after = rest.slice(1);
    if (!(after === "" || after[0] === " " || after[0] === "\t")) {
        return undefined;
    }
    const spaces = leadingSpaces(after);
    return {
        ordered: true,
        start: Number(digits),
        delimiter,
        width: digits.length + 1 + (after === "" || spaces > 4 ? 1 : spaces),
    };
}

function parseList(lines: string[], start: number, first: ListMarker, depth: number): [Block, number] {
    const items: Block[][] = [];
    let tight = true;
    let index = start;
    let marker = first;
    for (;;) {
        const indent = indentation(lines[index]!);
        const contentIndent = indent + marker.width;
        const itemLines = [[...stripIndentation(lines[index]!, indent)].slice(marker.width).join("")];
        index += 1;
        let sawBlank = false;
        while (index < lines.length) {
            const line = lines[index]!;
            if (isBlank(line)) {
                itemLines.push("");
                sawBlank = true;
                index += 1;
                continue;
            }
            if (indentation(line) >= contentIndent) {
                if (sawBlank) {
                    tight = false;
                }
                itemLines.push(stripIndentation(line, contentIndent));
                sawBlank = false;
                index += 1;
                continue;
            }
            const candidate = stripIndentation(line, 3);
            if (!sawBlank && !startsBlock(candidate) && listMarker(candidate) === undefined) {
                // A lazy continuation of the item's paragraph.
                itemLines.push(candidate);
                index += 1;
                continue;
            }
            break;
        }
        while (itemLines.length > 0 && isBlank(itemLines[itemLines.length - 1]!)) {
            itemLines.pop();
        }
        items.push(
            depth < maxDepth ? parseBlocks(itemLines, depth + 1) : [{ kind: "paragraph", text: itemLines.join("\n") }],
        );

        if (index >= lines.length || indentation(lines[index]!) >= contentIndent) {
            break;
        }
        const next = listMarker(stripIndentation(lines[index]!, 3));
        if (!next || next.ordered !== first.ordered || next.delimiter !== first.delimiter) {
            break;
        }
        if (sawBlank) {
            tight = false;
        }
        marker = next;
    }
    return [{ kind: "list", ordered: first.ordered, start: first.start, items, tight }, index];
}

function isBlank(line: string): boolean {
    return /^[ \t]*$/.test(line);
}

/** The line's leading whitespace in columns, with tabs to the next multiple of four. */
function indentation(line: string): number {
    let columns = 0;
    for (const character of line) {
        if (character === " ") {
            columns += 1;
        } else if (character === "\t") {
            columns += 4 - (columns % 4);
        } else {
            break;
        }
    }
    return columns;
}

/** The line without up to `columns` columns of leading whitespace. */
function stripIndentation(line: string, columns: number): string {
    let removed = 0;
    let index = 0;
    while (index < line.length && removed < columns) {
        const character = line[index];
        if (character === " ") {
            removed += 1;
        } else if (character === "\t") {
            removed += 4 - (removed % 4);
        } else {
            break;
        }
        index += 1;
    }
    return line.slice(index);
}

/** Whether a line would start a block other than a paragraph, and so interrupts one. */
function startsBlock(content: string): boolean {
    if (content.startsWith(">") || fence(content) || atxHeading(content) || isThematicBreak(content)) {
        return true;
    }
    const marker = listMarker(content);
    if (marker) {
        // An empty item or one not starting at 1 can't interrupt a paragraph.
        const rest = content.slice(marker.width);
        return !isBlank(rest) && (!marker.ordered || marker.start === 1);
    }
    return false;
}

function fence(content: string): { character: string; length: number; info: string | undefined } | undefined {
    const character = content[0];
    if (character !== "`" && character !== "~") {
        return undefined;
    }
    const length = (character === "`" ? /^`*/ : /^~*/).exec(content)![0].length;
    if (length < 3) {
        return undefined;
    }
    const info = trimSpaces(content.slice(length));
    if (character === "`" && info.includes("`")) {
        return undefined;
    }
    return { character, length, info: info.split(" ").filter(Boolean)[0] };
}

function atxHeading(content: string): { level: number; text: string } | undefined {
    const level = /^#*/.exec(content)![0].length;
    if (level < 1 || level > 6) {
        return undefined;
    }
    const rest = content.slice(level);
    if (!(rest === "" || rest[0] === " " || rest[0] === "\t")) {
        return undefined;
    }
    let text = trimSpaces(rest);
    // A closing run of #s, after a space, isn't part of the heading.
    const trailing = /#*$/.exec(text)![0].length;
    if (trailing > 0) {
        const without = text.slice(0, text.length - trailing);
        if (without === "" || without.endsWith(" ")) {
            text = trimSpaces(without);
        }
    }
    return { level, text };
}

function isThematicBreak(content: string): boolean {
    const marks = content.replace(/[ \t]/g, "");
    const first = marks[0];
    if (first !== "-" && first !== "*" && first !== "_") {
        return false;
    }
    return marks.length >= 3 && [...marks].every((c) => c === first);
}

function setextLevel(content: string): number | undefined {
    const trimmed = trimSpaces(content);
    const first = trimmed[0];
    if ((first !== "=" && first !== "-") || ![...trimmed].every((c) => c === first)) {
        return undefined;
    }
    return first === "=" ? 1 : 2;
}

function tableDelimiter(line: string): Alignment[] | undefined {
    const row = cells(stripIndentation(line, 3));
    if (row.length === 0 || !line.includes("-")) {
        return undefined;
    }
    const alignments: Alignment[] = [];
    for (const cell of row) {
        const left = cell.startsWith(":");
        const right = cell.endsWith(":");
        const dashes = cell.replace(/^:+|:+$/g, "");
        if (!/^-+$/.test(dashes)) {
            return undefined;
        }
        alignments.push(left && right ? "center" : right ? "right" : left ? "left" : null);
    }
    return alignments;
}

/** The cells of a table row, without the outer pipes. A pipe escaped with a backslash stays in its cell. */
function cells(line: string): string[] {
    let trimmed = trimSpaces(line);
    if (trimmed.startsWith("|")) {
        trimmed = trimmed.slice(1);
    }
    if (trimmed.endsWith("|") && !trimmed.endsWith("\\|")) {
        trimmed = trimmed.slice(0, -1);
    }
    const result: string[] = [];
    let current = "";
    let escaped = false;
    for (const character of trimmed) {
        if (escaped) {
            current += character === "|" ? "|" : `\\${character}`;
            escaped = false;
        } else if (character === "\\") {
            escaped = true;
        } else if (character === "|") {
            result.push(trimSpaces(current));
            current = "";
        } else {
            current += character;
        }
    }
    if (escaped) {
        current += "\\";
    }
    result.push(trimSpaces(current));
    return result;
}

/** The text of an HTML block, without its tags and comments. */
function textOfHtml(html: string): string {
    let text = "";
    let inTag = false;
    let index = 0;
    while (index < html.length) {
        if (!inTag && html.startsWith("<!--", index)) {
            const end = html.indexOf("-->", index);
            if (end < 0) {
                break;
            }
            index = end + 3;
            continue;
        }
        const character = html[index]!;
        if (character === "<") {
            inTag = true;
        } else if (character === ">" && inTag) {
            inTag = false;
            text += " ";
        } else if (!inTag) {
            text += character;
        }
        index += 1;
    }
    return text.split(/\s+/u).filter(Boolean).join(" ");
}

// MARK: Rendering

function renderBlocks(blocks: Block[], inline: Inline): string {
    return blocks.map((block) => renderBlock(block, inline)).join("\n");
}

function renderBlock(block: Block, inline: Inline): string {
    switch (block.kind) {
        case "heading": {
            const anchor = block.id === undefined ? "" : ` id="${escapeXhtml(block.id)}"`;
            return `<h${block.level}${anchor}>${inline.render(block.text)}</h${block.level}>`;
        }
        case "paragraph":
            return `<p>${inline.render(block.text)}</p>`;
        case "code": {
            const type = block.language === undefined ? "" : ` class="language-${escapeXhtml(block.language)}"`;
            return `<pre><code${type}>${escapeXhtml(block.text)}</code></pre>`;
        }
        case "quote":
            return `<blockquote>\n${renderBlocks(block.blocks, inline)}\n</blockquote>`;
        case "list": {
            const tag = block.ordered ? "ol" : "ul";
            const start = block.ordered && block.start !== 1 ? ` start="${block.start}"` : "";
            const items = block.items.map((item) => {
                if (block.tight) {
                    // Tight lists show their paragraphs without spacing.
                    const parts = item.map((part) =>
                        part.kind === "paragraph" ? inline.render(part.text) : renderBlock(part, inline),
                    );
                    return `<li>${parts.join("\n")}</li>`;
                }
                return `<li>${renderBlocks(item, inline)}</li>`;
            });
            return `<${tag}${start}>\n${items.join("\n")}\n</${tag}>`;
        }
        case "table": {
            const cell = (tag: string, text: string, column: number) => {
                const alignment = block.alignments[column] ?? null;
                const style = alignment ? ` style="text-align: ${alignment}"` : "";
                return `<${tag}${style}>${inline.render(text)}</${tag}>`;
            };
            const head = block.header.map((text, column) => cell("th", text, column)).join("");
            const rows = block.rows.map((row) => `<tr>${row.map((text, column) => cell("td", text, column)).join("")}</tr>`);
            return `<table>\n<thead><tr>${head}</tr></thead>\n<tbody>\n${rows.join("\n")}\n</tbody>\n</table>`;
        }
        case "rule":
            return "<hr/>";
    }
}

// MARK: Inline

const isWhitespace = (c: string) => /\s/u.test(c);
const isWord = (c: string) => /[\p{L}\p{N}]/u.test(c);

/** The named entities documents commonly use. XHTML only defines the five XML ones, so the rest become their characters. */
const entities: Record<string, string> = {
    amp: "&amp;", lt: "&lt;", gt: "&gt;", quot: "&quot;", apos: "&#39;",
    nbsp: " ", copy: "©", reg: "®", trade: "™", mdash: "—", ndash: "–",
    hellip: "…", lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", laquo: "«",
    raquo: "»", deg: "°", times: "×", middot: "·", bull: "•", sect: "§", para: "¶",
};

/** Emphasis nested deeper than this is left as text. */
const maxInlineDepth = 16;

/** Renders Markdown's inline syntax as XHTML: emphasis, code, links, images, line breaks and escapes. */
class Inline {
    /** `resolveLink` rewrites a link's destination, or returns null to drop the link and keep its text. */
    constructor(private readonly resolveLink: (destination: string) => string | null) {}

    render(text: string): string {
        return this.renderCharacters([...text], 0);
    }

    private renderCharacters(text: string[], depth: number): string {
        let html = "";
        let index = 0;
        while (index < text.length) {
            const character = text[index]!;
            const next = text[index + 1];
            if (character === "\\") {
                if (next === "\n") {
                    html += "<br/>\n";
                    index += 2;
                } else if (next !== undefined && /[\p{P}\p{S}]/u.test(next)) {
                    html += escapeXhtml(next);
                    index += 2;
                } else {
                    html += "\\";
                    index += 1;
                }
            } else if (character === "`") {
                const run = runLength(text, index);
                const close = findRun("`", run, text, index + run);
                if (close !== undefined) {
                    let code = text.slice(index + run, close).join("").replace(/\n/g, " ");
                    if ([...code].length > 2 && code.startsWith(" ") && code.endsWith(" ")) {
                        code = code.slice(1, -1);
                    }
                    html += `<code>${escapeXhtml(code)}</code>`;
                    index = close + run;
                } else {
                    html += "`".repeat(run);
                    index += run;
                }
            } else if (character === "!" && next === "[") {
                const link = parseLink(text, index + 1);
                if (link) {
                    // A Markdown file is read on its own, so images it points
                    // at can't be loaded. Its description stands in.
                    const alt = text.slice(link.labelStart, link.labelEnd).join("");
                    if (alt) {
                        html += `<span class="image">${escapeXhtml(alt)}</span>`;
                    }
                    index = link.end;
                } else {
                    html += "!";
                    index += 1;
                }
            } else if (character === "[") {
                const link = parseLink(text, index);
                if (link) {
                    const label = this.renderCharacters(text.slice(link.labelStart, link.labelEnd), depth + 1);
                    const href = this.resolveLink(link.destination);
                    if (href !== null) {
                        const title = link.title === undefined ? "" : ` title="${escapeXhtml(link.title)}"`;
                        html += `<a href="${escapeXhtml(href)}"${title}>${label}</a>`;
                    } else {
                        html += label;
                    }
                    index = link.end;
                } else {
                    html += "[";
                    index += 1;
                }
            } else if (character === "<") {
                const close = text.indexOf(">", index);
                const contents = close < 0 ? "" : text.slice(index + 1, close).join("");
                const url = close < 0 ? undefined : autolink(contents);
                if (url !== undefined) {
                    const shown = escapeXhtml(contents);
                    const href = this.resolveLink(url);
                    html += href !== null ? `<a href="${escapeXhtml(href)}">${shown}</a>` : shown;
                    index = close + 1;
                } else {
                    html += "&lt;";
                    index += 1;
                }
            } else if (character === "*" || character === "_" || character === "~") {
                const run = runLength(text, index);
                const match = emphasis(text, index, run, depth);
                if (match) {
                    const [tag, length, close] = match;
                    const inner = this.renderCharacters(text.slice(index + length, close), depth + 1);
                    html += `<${tag}>${inner}</${tag}>`;
                    index = close + length;
                } else {
                    html += character.repeat(run);
                    index += run;
                }
            } else if (character === "&") {
                const [decoded, length] = entity(text, index);
                html += decoded;
                index += length;
            } else if (character === "\n") {
                // Two trailing spaces make a hard break.
                if (html.endsWith("  ")) {
                    html = html.replace(/ +$/, "") + "<br/>\n";
                } else {
                    html += "\n";
                }
                index += 1;
            } else {
                html += escapeXhtml(character);
                index += 1;
            }
        }
        return html;
    }
}

function runLength(text: string[], index: number): number {
    let end = index;
    while (end < text.length && text[end] === text[index]) {
        end += 1;
    }
    return end - index;
}

/** The tag, delimiter length and closing index for emphasis opening at `index`, or undefined when it doesn't open any. */
function emphasis(text: string[], index: number, run: number, depth: number): [string, number, number] | undefined {
    if (depth >= maxInlineDepth) {
        return undefined;
    }
    const character = text[index]!;
    const after = text[index + run] ?? " ";
    if (isWhitespace(after)) {
        return undefined;
    }
    // An underscore inside a word, as in snake_case, isn't emphasis.
    if (character === "_" && index > 0 && isWord(text[index - 1]!)) {
        return undefined;
    }
    const candidates: [string, number][] =
        character === "~" ? (run >= 2 ? [["del", 2]] : []) : run >= 2 ? [["strong", 2], ["em", 1]] : [["em", 1]];
    for (const [tag, length] of candidates) {
        const close = closing(character, length, text, index + length);
        if (close !== undefined) {
            return [tag, length, close];
        }
    }
    return undefined;
}

/** The next run of exactly `length` delimiters that can close emphasis: it follows something other than whitespace. */
function closing(character: string, length: number, text: string[], start: number): number | undefined {
    let index = start;
    while (index < text.length) {
        if (text[index] === "`") {
            // Delimiters inside code spans don't count.
            const run = runLength(text, index);
            index = (findRun("`", run, text, index + run) ?? index) + run;
            continue;
        }
        if (text[index] !== character) {
            index += 1;
            continue;
        }
        const run = runLength(text, index);
        if (run === length && index > start && !isWhitespace(text[index - 1]!)) {
            const next = index + run;
            if (character !== "_" || next >= text.length || !isWord(text[next]!)) {
                return index;
            }
        }
        index += run;
    }
    return undefined;
}

function findRun(character: string, length: number, text: string[], start: number): number | undefined {
    let index = start;
    while (index < text.length) {
        if (text[index] === character) {
            const run = runLength(text, index);
            if (run === length) {
                return index;
            }
            index += run;
        } else {
            index += 1;
        }
    }
    return undefined;
}

/** An inline link, `[label](destination "title")`, starting at the `[`. */
function parseLink(
    text: string[],
    start: number,
): { labelStart: number; labelEnd: number; destination: string; title?: string; end: number } | undefined {
    let depth = 0;
    let index = start;
    let labelEnd: number | undefined;
    while (index < text.length) {
        const character = text[index];
        if (character === "\\") {
            index += 1;
        } else if (character === "[") {
            depth += 1;
        } else if (character === "]") {
            depth -= 1;
            if (depth === 0) {
                labelEnd = index;
                break;
            }
        }
        index += 1;
    }
    if (labelEnd === undefined || text[labelEnd + 1] !== "(") {
        return undefined;
    }
    const close = matchingParenthesis(text, labelEnd + 1);
    if (close === undefined) {
        return undefined;
    }
    let inside = text.slice(labelEnd + 2, close).join("").trim();
    let title: string | undefined;
    const quote = inside[inside.length - 1];
    if (quote === '"' || quote === "'") {
        const open = inside.slice(0, -1).lastIndexOf(quote);
        if (open > 0 && isWhitespace(inside[open - 1]!)) {
            title = inside.slice(open + 1, -1);
            inside = trimSpaces(inside.slice(0, open));
        }
    }
    if (inside.startsWith("<") && inside.endsWith(">")) {
        inside = inside.slice(1, -1);
    }
    return { labelStart: start + 1, labelEnd, destination: inside, title, end: close + 1 };
}

function matchingParenthesis(text: string[], open: number): number | undefined {
    let depth = 0;
    let index = open;
    while (index < text.length) {
        const character = text[index];
        if (character === "\\") {
            index += 1;
        } else if (character === "(") {
            depth += 1;
        } else if (character === ")") {
            depth -= 1;
            if (depth === 0) {
                return index;
            }
        } else if (character === "\n" && depth > 0 && text[index + 1] === "\n") {
            return undefined;
        }
        index += 1;
    }
    return undefined;
}

/** The URL of an autolink's contents, such as `https://example.com` or `someone@example.com`, or undefined when it isn't one. */
function autolink(contents: string): string | undefined {
    if (!contents || /[\s<]/u.test(contents)) {
        return undefined;
    }
    const colon = contents.indexOf(":");
    if (colon >= 2 && /^[A-Za-z0-9+.-]+$/.test(contents.slice(0, colon))) {
        return contents;
    }
    if (contents.includes("@") && !contents.includes("/")) {
        return `mailto:${contents}`;
    }
    return undefined;
}

/** An entity reference at `index` as XHTML, and how many characters it took. A lone `&` is escaped. */
function entity(text: string[], index: number): [string, number] {
    let end = index + 1;
    while (end < text.length && end - index <= 32 && /^[A-Za-z0-9#]$/.test(text[end]!)) {
        end += 1;
    }
    if (end >= text.length || text[end] !== ";" || end <= index + 1) {
        return ["&amp;", 1];
    }
    const name = text.slice(index + 1, end).join("");
    if (name.startsWith("#")) {
        const digits = name.slice(1);
        const hex = digits.toLowerCase().startsWith("x");
        const source = hex ? digits.slice(1) : digits;
        const value = (hex ? /^[0-9a-fA-F]+$/ : /^[0-9]+$/).test(source) ? parseInt(source, hex ? 16 : 10) : NaN;
        if (value > 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff)) {
            return [escapeXhtml(String.fromCodePoint(value)), end - index + 1];
        }
        return ["&amp;", 1];
    }
    const replacement = entities[name];
    return replacement === undefined ? ["&amp;", 1] : [replacement, end - index + 1];
}

/** Markdown blocks as XHTML, without chapters or link rewriting. For tests. */
export function markdownHtml(text: string): string {
    return renderBlocks(parseBlocks(text.split("\n"), 0), new Inline((destination) => destination));
}

/** Ids for headings, as chapters give them. For tests. */
export function makeSlugs(): { make(text: string): string } {
    return new Slugs();
}
