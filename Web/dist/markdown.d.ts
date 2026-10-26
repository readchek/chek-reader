import type { BookMetadata, TocItem } from "./publication.js";
import { type TextDocument } from "./text.js";
/** Converts a Markdown file into chapters, contents and metadata. */
export declare function renderMarkdown(text: string, fileName: string | undefined): {
    metadata: BookMetadata;
    documents: TextDocument[];
    toc: TocItem[];
};
/** A heading's text without its Markdown, for titles. */
export declare function plain(text: string): string;
/** Markdown blocks as XHTML, without chapters or link rewriting. For tests. */
export declare function markdownHtml(text: string): string;
/** Ids for headings, as chapters give them. For tests. */
export declare function makeSlugs(): {
    make(text: string): string;
};
