import type { Edge } from "./flow.js";
import type { Publication, TocItem } from "./publication.js";
import type { Locator } from "./locator.js";
/** Reading settings, as the Swift package's ReaderPreferences. */
export interface BookPreferences {
    /** Text size relative to the publication's, where 1 is unchanged. */
    fontScale: number;
    /** `default` keeps the publication's colors. */
    theme: "default" | "light" | "sepia" | "dark";
    /** `default` keeps the publication's fonts. */
    font: "default" | "serif" | "sans";
    /** Line height as a multiple of the text size; 0 keeps the publication's. */
    lineHeight: number;
    /** Multiplies the page margins; 1 keeps the standard ones. */
    marginScale: number;
}
export declare const defaultBookPreferences: BookPreferences;
/** Where the reader is. */
export interface BookLocation {
    locator: Locator;
    /** The reading order index of the resource on screen. */
    resource: number;
    /** The page within the resource, from 0, and how many it has. */
    page: number;
    pageCount: number;
    /** The 1-based position, and how many the book has: fixed points that don't move with the text size. */
    position: number;
    positionCount: number;
    /** The table of contents entry the page is in, if any. */
    chapter: TocItem | undefined;
    atStart: boolean;
    atEnd: boolean;
    /** The end that's on screen in place of the page, when the reader has turned onto one. */
    edge: Edge | null;
}
export interface BookEvents {
    /** The reader moved, or the page changed under it. */
    location(location: BookLocation): void;
    /** A tap in the middle of the page, for showing controls. */
    tap(): void;
    /**
     * The mouse moved over the book's page, for showing controls on hover.
     * The page is in a frame of its own, so the app's document doesn't see
     * these moves. Touches don't count. Sent at most every 100 ms.
     */
    pointer(): void;
    /** A turn past the last page when nothing is given to show after it. */
    end(): void;
    /**
     * Reading on past what's after the last page, or back past what's
     * before the first, which apps use to open the next or previous book
     * or chapter. Only an end that was given can be left through.
     */
    leave(toward: Edge): void;
    /** A link out of the book, to open elsewhere. */
    externalLink(url: string): void;
    /**
     * A key pressed on the book's page that the reader doesn't use, such as
     * Escape, named as `KeyboardEvent.key` names it. The page is in a frame
     * of its own, so the app's document doesn't see these keys while the
     * page has focus. Keys pressed elsewhere reach the app as usual.
     */
    key(key: string): void;
    error(error: unknown): void;
}
export interface BookOptions {
    /** The address of the reader's frame page, served by the app. */
    frameUrl: string;
    preferences: BookPreferences;
    /**
     * What shows one turn before the first page and one turn after the
     * last, such as what joins one chapter to the next. The view places
     * the elements over the page and the app draws what's in them, as
     * `ComicView` does with its `ends`.
     */
    ends?: {
        before?: HTMLElement;
        after?: HTMLElement;
    };
}
export declare class BookView {
    private readonly element;
    private readonly book;
    private readonly events;
    private readonly options;
    private readonly slots;
    private current;
    private nextId;
    private generation;
    private preferences;
    private queue;
    private readonly starts;
    private readonly positionCount;
    private destroyed;
    private lastLocation;
    /** The end the reader has turned onto, shown over the page it came from. */
    private edge;
    private readonly ends;
    private lastLeft;
    private lastWheel;
    constructor(element: HTMLElement, book: Publication, events: Partial<BookEvents>, options: BookOptions, start: Locator | null);
    /** Where the reader is, once the first page is on screen. */
    get location(): BookLocation | undefined;
    next(): Promise<void>;
    previous(): Promise<void>;
    /** Goes to a place saved earlier, by its text when it has some, else its progression. */
    goTo(locator: Locator): Promise<void>;
    /** Goes to an href in the book, such as a table of contents entry's. */
    goToHref(href: string): Promise<void>;
    /** The table of contents entry at a point through the whole book, from 0 to 1, such as for a slider's label. */
    chapterAt(total: number): TocItem | undefined;
    /** Goes to a point through the whole book, from 0 to 1. */
    goToProgression(total: number): Promise<void>;
    setPreferences(preferences: Partial<BookPreferences>): Promise<void>;
    destroy(): void;
    private enqueue;
    private open;
    /**
     * An end's element, which sits over the page and so takes the taps,
     * swipes and wheel the page's own frame would have.
     */
    private edgeHolder;
    /** Shows an end over the page, or takes it away, and says so. */
    private setEdge;
    private leave;
    private turn;
    /** The resource and progression within it at a point through the whole book. */
    private resourceAt;
    private show;
    private preload;
    /** The slot holding `index`, loading the resource into one when none does. */
    private load;
    private call;
    private request;
    private readonly receive;
    private input;
    private keyStep;
    private readonly keydown;
    private report;
    /** The deepest table of contents entry for a resource. */
    private chapterOf;
    private flatToc;
}
