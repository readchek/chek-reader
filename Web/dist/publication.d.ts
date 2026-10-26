/** A resource in the reading order. */
export interface ReadingOrderItem {
    /** The resource's path from the publication's root, as locators name it. */
    href: string;
    type: string;
    /** Whether it's a fixed-layout page, scaled to fit, rather than reflowable text. */
    fixed: boolean;
    /** How many positions it holds: one per 1,024 bytes of text, as Readium and the Swift package count. */
    positions: number;
}
/** An entry in the table of contents. `href` may carry a fragment. */
export interface TocItem {
    title: string;
    href: string;
    children: TocItem[];
}
export interface BookMetadata {
    title: string;
    authors: string[];
    language: string | null;
    readingProgression: "ltr" | "rtl";
}
/** A publication the book view can show. */
export interface Publication {
    readonly metadata: BookMetadata;
    readonly readingOrder: ReadingOrderItem[];
    readonly toc: TocItem[];
    /** A resource's bytes, by its path from the publication's root. */
    resource(path: string): Promise<Blob>;
    has(path: string): boolean;
    /** A resource's media type. */
    typeOf(path: string): string;
    /** The index of a resource in the reading order, or -1. */
    indexOf(path: string): number;
    /** How many positions the whole publication holds. */
    readonly positionCount: number;
}
