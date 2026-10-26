import { type Locator } from "./locator.js";
/** Where a comic's pages come from, such as a server's page endpoint. */
export interface PageSource {
    /** How many pages the comic has. */
    readonly count: number;
    /** The page's image. Called again after a failure, so it may retry. */
    load(index: number, signal: AbortSignal): Promise<Blob>;
}
/**
 * How pages follow one another. `automatic` scrolls webtoons, whose pages
 * are tall strips, and turns pages for everything else, as the Swift
 * package's `ComicFlow` does.
 */
export type ComicFlow = "automatic" | "paged" | "scrolled";
/** Which way pages turn. Manga reads right to left. */
export type ReadingDirection = "ltr" | "rtl";
/** Whether two pages show side by side. `automatic` shows them when the element is wider than it is tall. */
export type Spreads = "automatic" | "single" | "double";
export interface ComicOptions {
    flow: ComicFlow;
    direction: ReadingDirection;
    spreads: Spreads;
}
/** Where the reader is, reported after every move. */
export interface ComicLocation {
    /** The first page on screen, from 0. */
    page: number;
    /** Every page on screen, in reading order. */
    pages: number[];
    count: number;
    locator: Locator;
    /** Whether the last page is on screen. */
    atEnd: boolean;
}
export interface ComicEvents {
    location(location: ComicLocation): void;
    /** A tap or click in the middle of the page, which apps use to show their controls. */
    tap(): void;
    /** Turning past the last page, which apps use to offer what's next. */
    end(): void;
    /** A page that couldn't be loaded. It's tried again when it's next shown. */
    error(page: number, error: unknown): void;
}
/**
 * A comic's pages in `element`, which needs a size of its own, such as the
 * whole window, and a position other than static, since pages are laid
 * over it. Call `destroy` when it goes away.
 */
export declare class ComicView {
    private readonly element;
    private readonly source;
    private readonly events;
    private options;
    private readonly pages;
    private readonly loaded;
    private readonly controller;
    private start;
    private flow;
    private stage?;
    private strip?;
    private observer?;
    private resizer;
    private spreadsShown;
    private generation;
    private zoom;
    private lastReported;
    constructor(element: HTMLElement, source: PageSource, events?: Partial<ComicEvents>, options?: Partial<ComicOptions>, start?: Locator | number | null);
    /** The first page on screen, from 0. */
    get page(): number;
    get count(): number;
    /** The flow in use, with `automatic` decided. */
    get currentFlow(): "paged" | "scrolled";
    /** Changes how pages are laid out, keeping the page on screen. */
    setOptions(options: Partial<ComicOptions>): void;
    /** Shows the page at `index`, from 0. */
    goTo(index: number): void;
    /** Shows the next page or spread. Returns false at the end. */
    next(): boolean;
    /** Shows the previous page or spread. Returns false at the start. */
    previous(): boolean;
    /** The position of the first page on screen. */
    locator(): Locator;
    destroy(): void;
    private load;
    /** Lets go of decoded pages outside the window around `center`. */
    private trim;
    private setUp;
    private looksLikeWebtoon;
    private wantsSpreads;
    private relayout;
    private status;
    /** Shows the screen that starts at `start`. `motion` is 1 going forward, -1 back, 0 for a jump. */
    private show;
    private slideIn;
    private buildStrip;
    private onScroll;
    private scrollBy;
    private report;
    private resetZoom;
    private applyZoom;
    /** Zooms to `scale`, keeping the point at (`px`, `py`) in the element where it is. */
    private zoomTo;
    private clampPan;
    private listen;
}
