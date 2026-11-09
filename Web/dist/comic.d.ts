import { type Edge } from "./flow.js";
import { type Locator } from "./locator.js";
/** Where a comic's pages come from, such as a server's page endpoint. */
export interface PageSource {
    /** How many pages the comic has. */
    readonly count: number;
    /** The page's image. Called again after a failure, so it may retry. */
    load(index: number, signal: AbortSignal): Promise<Blob>;
    /** The locator of a page, when the pages aren't a comic's, such as a PDF's. Comic locators by default. */
    locator?(index: number): Locator;
    /** The page a locator points at, read the way `locator` writes it. */
    pageIndex?(locator: Locator): number | undefined;
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
/**
 * What shows past either end of the pages, in the flow of reading: one
 * turn past the last page or before the first in a paged comic, and above
 * and below the column in a scrolled one. Apps use them to join one
 * chapter to the next, saying what was finished and what comes after. The
 * view places the elements and the app draws what's in them.
 */
export interface ComicEnds {
    before?: HTMLElement;
    after?: HTMLElement;
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
    /** The end that's on screen in place of pages, when a paged comic has turned onto one. */
    edge: Edge | null;
}
export interface ComicEvents {
    location(location: ComicLocation): void;
    /** A tap or click in the middle of the page, which apps use to show their controls. */
    tap(): void;
    /** Turning past the last page when nothing is given to show after it. */
    end(): void;
    /**
     * Reading on past what's after the last page, or back past what's
     * before the first, which apps use to open the next or previous
     * chapter. Only an end that was given can be left through.
     */
    leave(toward: Edge): void;
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
    /** The end a paged comic has turned onto, in place of pages. */
    private edge;
    /** The scrolled column's pages, in order, without what's above and below them. */
    private slots;
    private readonly ends;
    private lastLeft;
    /** Whether it opened at its end, read back into from what follows it. */
    private fromEnd;
    /**
     * Where a scrolled column was opened, held there while pages above
     * load and take their real heights, until the reader moves it.
     */
    private opened;
    constructor(element: HTMLElement, source: PageSource, events?: Partial<ComicEvents>, options?: Partial<ComicOptions>, start?: Locator | number | "end" | null, ends?: ComicEnds);
    /** The first page on screen, from 0. */
    get page(): number;
    get count(): number;
    /** The flow in use, with `automatic` decided. */
    get currentFlow(): "paged" | "scrolled";
    /** Changes how pages are laid out, keeping the page on screen. */
    setOptions(options: Partial<ComicOptions>): void;
    /** Shows the page at `index`, from 0. */
    goTo(index: number): void;
    /** Whether something shows before the first page or after the last. */
    private get edges();
    private turnPaged;
    /** Whether a key is held down, repeating. Holding one turns pages but never leaves them. */
    private held;
    private leave;
    /** Shows the next page or spread. Returns false at the end. */
    next(): boolean;
    /** Shows the previous page or spread. Returns false at the start. */
    previous(): boolean;
    /**
     * Zooms in or out by `factor` around the middle of the view, such as
     * for a zoom key. Only paged comics zoom; reaching 1 shows the whole
     * page again.
     */
    zoomBy(factor: number): void;
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
    /** Shows what's before the first page or after the last, as a screen of its own. */
    private showEdge;
    private slideIn;
    private buildStrip;
    private onScroll;
    /** Whether the column is scrolled as far as it goes, down (1) or up (-1). */
    private scrolledToEnd;
    private scrollBy;
    private report;
    private resetZoom;
    private applyZoom;
    /** Zooms to `scale`, keeping the point at (`px`, `py`) in the element where it is. */
    private zoomTo;
    private clampPan;
    private listen;
}
