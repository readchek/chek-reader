import { type ZipLimits } from "./zip.js";
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
/** The publication is protected by DRM, which the reader doesn't decrypt. */
export declare class DrmError extends Error {
}
/** The file isn't an EPUB the reader can open. */
export declare class EpubError extends Error {
}
/** An opened EPUB. */
export declare class Epub {
    private readonly archive;
    readonly metadata: BookMetadata;
    readonly readingOrder: ReadingOrderItem[];
    readonly toc: TocItem[];
    private readonly types;
    private constructor();
    static open(file: Blob, limits?: ZipLimits): Promise<Epub>;
    /** A resource's bytes, by its path from the publication's root. */
    resource(path: string): Promise<Blob>;
    has(path: string): boolean;
    /** A resource's media type, from the manifest or its extension. */
    typeOf(path: string): string;
    /** The index of a resource in the reading order, or -1. */
    indexOf(path: string): number;
    /** How many positions the whole publication holds. */
    get positionCount(): number;
}
