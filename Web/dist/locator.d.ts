/**
 * A position in a publication, as a [Readium Locator](https://readium.org/architecture/models/locators/).
 * It's the same JSON the Swift package's `Locator` reads and writes, so a
 * position saved on the web opens in the same place on iPhone, and back.
 */
export interface Locator {
    href: string;
    type: string;
    title?: string;
    locations?: {
        fragments?: string[];
        progression?: number;
        totalProgression?: number;
        /** Counts from 1. */
        position?: number;
    };
    text?: {
        before?: string;
        highlight?: string;
        after?: string;
    };
}
/**
 * The href of a comic's page when its pages come one by one from a page
 * source, as `PageSourceContainer` names them in the Swift package:
 * `pages/1` for the first.
 */
export declare function pageHref(index: number): string;
/** The locator at the start of a comic's page, as the Swift package's image navigator reports it. */
export declare function comicLocator(index: number, count: number, type?: string): Locator;
/**
 * The zero-based page a comic locator points at, or undefined when it
 * names no page of a comic with `count` pages. It reads the href first,
 * then the position, then the total progression, so positions saved by
 * older readers still open near where they were.
 */
export declare function comicPageIndex(locator: Locator | null | undefined, count: number): number | undefined;
/** The href of a PDF's one resource, as the Swift package's `PDFModule.href`. */
export declare const pdfHref = "publication.pdf";
/** The locator of a PDF's page, from 0, as the Swift package's PDF navigator reports it. */
export declare function pdfLocator(index: number, count: number, title?: string): Locator;
/** The page from 0 a PDF locator points at: its `page=N` fragment, else its position, else its progression. */
export declare function pdfPageIndex(locator: Locator | null | undefined, count: number): number | undefined;
