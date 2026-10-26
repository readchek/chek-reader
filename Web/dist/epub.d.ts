import type { BookMetadata, Publication, ReadingOrderItem, TocItem } from "./publication.js";
import { type ZipLimits } from "./zip.js";
/** The publication is protected by DRM, which the reader doesn't decrypt. */
export declare class DrmError extends Error {
}
/** The file isn't an EPUB the reader can open. */
export declare class EpubError extends Error {
}
/** An opened EPUB. */
export declare class Epub implements Publication {
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
