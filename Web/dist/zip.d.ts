/** Limits on what an archive may ask of the reader. */
export interface ZipLimits {
    /** The most entries the directory may list. */
    entries: number;
    /** The largest an entry may inflate to, in bytes. */
    entrySize: number;
}
export declare const defaultZipLimits: ZipLimits;
/** The archive isn't a ZIP the reader can read, or breaks a limit. */
export declare class ZipError extends Error {
}
export declare class ZipArchive {
    private readonly blob;
    private readonly entries;
    private readonly limits;
    private constructor();
    /** Reads the archive's directory. */
    static open(blob: Blob, limits?: ZipLimits): Promise<ZipArchive>;
    /** Every entry's path, in the order the directory lists them. */
    get paths(): string[];
    has(path: string): boolean;
    /** An entry's inflated size, as the directory gives it. */
    size(path: string): number | undefined;
    /** An entry's bytes, inflated, as a Blob of `type`. */
    read(path: string, type?: string): Promise<Blob>;
    text(path: string): Promise<string>;
}
