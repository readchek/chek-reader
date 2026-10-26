import type { PageSource } from "./comic.js";
import { type Locator } from "./locator.js";
import type { TocItem } from "./publication.js";
/** Where pdf.js's own files are served from your app's origin. */
export interface PdfFiles {
    /** pdf.js's worker, `pdfjs-dist/build/pdf.worker.min.mjs`. */
    worker: string;
    /** The folder holding `pdfjs-dist/cmaps`, ending in `/`, for PDFs in Chinese, Japanese and Korean without embedded fonts. */
    cMaps?: string;
    /** The folder holding `pdfjs-dist/standard_fonts`, ending in `/`, for PDFs that use the standard fonts without embedding them. */
    standardFonts?: string;
}
/** The PDF can't be opened, such as when it's damaged or needs a password. */
export declare class PdfError extends Error {
}
/** An opened PDF: its pages for `ComicView`, its outline and its title. */
export declare class PdfDocument implements PageSource {
    private readonly document;
    /** The title from the PDF's information, or an empty string. */
    readonly title: string;
    /** The outline, with hrefs such as `publication.pdf#page=3`. */
    readonly toc: TocItem[];
    /** For each outline entry with a page, the page from 0, in page order. */
    private readonly sections;
    private constructor();
    static open(file: Blob, files: PdfFiles): Promise<PdfDocument>;
    get count(): number;
    /** The outline entry a page is in, as the Swift package titles its locators. */
    sectionTitle(index: number): string | undefined;
    load(index: number, signal: AbortSignal): Promise<Blob>;
    locator(index: number): Locator;
    pageIndex(locator: Locator): number | undefined;
    /** Frees pdf.js's copy of the file and its worker. */
    destroy(): Promise<void>;
}
