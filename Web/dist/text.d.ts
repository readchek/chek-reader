import type { BookMetadata, Publication, ReadingOrderItem, TocItem } from "./publication.js";
/** A converted document: its path and XHTML. */
export interface TextDocument {
    href: string;
    xhtml: string;
}
/** Plain text or Markdown, opened as a publication of XHTML documents. */
export declare class TextBook implements Publication {
    readonly metadata: BookMetadata;
    readonly toc: TocItem[];
    private readonly resources;
    readonly readingOrder: ReadingOrderItem[];
    private constructor();
    /**
     * Opens plain text. Headings such as "Chapter 12" or "PART TWO" split it
     * into chapters and make the contents. Text can be UTF-8, UTF-16 with a
     * byte order mark, or Windows-1252.
     */
    static plainText(file: Blob, fileName?: string): Promise<TextBook>;
    /**
     * Opens Markdown, with a chapter per top-level heading and metadata from
     * YAML front matter. Raw HTML is reduced to its text, and images show
     * their description, since the file is read on its own.
     */
    static markdown(file: Blob, fileName?: string): Promise<TextBook>;
    resource(path: string): Promise<Blob>;
    has(path: string): boolean;
    typeOf(path: string): string;
    indexOf(path: string): number;
    get positionCount(): number;
}
/**
 * The text in `bytes`: by its byte order mark when it has one, else as
 * UTF-8, else as Windows-1252, the usual encoding of older text files.
 * Line endings become `\n`.
 */
export declare function decodeText(bytes: ArrayBuffer): string;
/** A title made from a file name: without its extension, and with underscores as spaces. */
export declare function titleFromFileName(fileName: string | undefined): string | undefined;
/** Escapes text for XHTML, dropping control characters XML doesn't allow. */
export declare function escapeXhtml(text: string): string;
/** A complete XHTML document around `body`, byte for byte as the Swift package's XHTML.document. */
export declare function xhtmlDocument(title: string | undefined, language: string | undefined, body: string): string;
/** The number of characters as Swift counts them, by grapheme cluster. */
export declare function characterCount(text: string): number;
export declare function partHref(prefix: string, index: number): string;
/** Trims spaces and tabs, as Swift's `.whitespaces` does, leaving line breaks. */
export declare function trimSpaces(text: string): string;
