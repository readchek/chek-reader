// A ZIP reader over a Blob, enough for EPUB: it reads the central
// directory, then each entry on demand, inflating with the browser's own
// DecompressionStream. Sizes and offsets come from the file, so each one is
// checked against the archive and the limits before it's used.

/** Limits on what an archive may ask of the reader. */
export interface ZipLimits {
    /** The most entries the directory may list. */
    entries: number;
    /** The largest an entry may inflate to, in bytes. */
    entrySize: number;
}

export const defaultZipLimits: ZipLimits = { entries: 20_000, entrySize: 256 * 1024 * 1024 };

interface Entry {
    method: number;
    compressedSize: number;
    size: number;
    /** Where the entry's local header starts. */
    offset: number;
}

/** The archive isn't a ZIP the reader can read, or breaks a limit. */
export class ZipError extends Error {}

const endSignature = 0x06054b50;
const centralSignature = 0x02014b50;
const localSignature = 0x04034b50;

export class ZipArchive {
    private constructor(
        private readonly blob: Blob,
        private readonly entries: Map<string, Entry>,
        private readonly limits: ZipLimits,
    ) {}

    /** Reads the archive's directory. */
    static async open(blob: Blob, limits: ZipLimits = defaultZipLimits): Promise<ZipArchive> {
        // The end record sits in the last 22 bytes plus a comment of up to 64 KiB.
        const tailStart = Math.max(0, blob.size - 22 - 0xffff);
        const tail = new DataView(await blob.slice(tailStart).arrayBuffer());
        let end = -1;
        for (let index = tail.byteLength - 22; index >= 0; index -= 1) {
            if (tail.getUint32(index, true) === endSignature) {
                end = index;
                break;
            }
        }
        if (end < 0) {
            throw new ZipError("This file isn't a ZIP archive, or it's cut short.");
        }
        const count = tail.getUint16(end + 10, true);
        const directorySize = tail.getUint32(end + 12, true);
        const directoryOffset = tail.getUint32(end + 16, true);
        if (count === 0xffff || directoryOffset === 0xffffffff) {
            throw new ZipError("ZIP64 archives aren't supported.");
        }
        if (count > limits.entries) {
            throw new ZipError(`The archive lists ${count} entries, more than the limit of ${limits.entries}.`);
        }
        if (directoryOffset + directorySize > blob.size) {
            throw new ZipError("The archive's directory points past its end.");
        }
        const directory = new DataView(
            await blob.slice(directoryOffset, directoryOffset + directorySize).arrayBuffer(),
        );
        const decoder = new TextDecoder();
        const entries = new Map<string, Entry>();
        let at = 0;
        for (let index = 0; index < count; index += 1) {
            if (at + 46 > directory.byteLength || directory.getUint32(at, true) !== centralSignature) {
                throw new ZipError("The archive's directory is damaged.");
            }
            const method = directory.getUint16(at + 10, true);
            const compressedSize = directory.getUint32(at + 20, true);
            const size = directory.getUint32(at + 24, true);
            const nameLength = directory.getUint16(at + 28, true);
            const extraLength = directory.getUint16(at + 30, true);
            const commentLength = directory.getUint16(at + 32, true);
            const offset = directory.getUint32(at + 42, true);
            const nameEnd = at + 46 + nameLength;
            if (nameEnd > directory.byteLength) {
                throw new ZipError("The archive's directory is damaged.");
            }
            const name = decoder.decode(new Uint8Array(directory.buffer, directory.byteOffset + at + 46, nameLength));
            if (!name.endsWith("/") && offset < blob.size) {
                entries.set(name, { method, compressedSize, size, offset });
            }
            at = nameEnd + extraLength + commentLength;
        }
        return new ZipArchive(blob, entries, limits);
    }

    /** Every entry's path, in the order the directory lists them. */
    get paths(): string[] {
        return [...this.entries.keys()];
    }

    has(path: string): boolean {
        return this.entries.has(path);
    }

    /** An entry's inflated size, as the directory gives it. */
    size(path: string): number | undefined {
        return this.entries.get(path)?.size;
    }

    /** An entry's bytes, inflated, as a Blob of `type`. */
    async read(path: string, type = ""): Promise<Blob> {
        const entry = this.entries.get(path);
        if (!entry) {
            throw new ZipError(`The archive has no entry ${path}.`);
        }
        if (entry.size > this.limits.entrySize) {
            throw new ZipError(`${path} is larger than the limit of ${this.limits.entrySize} bytes.`);
        }
        const header = new DataView(await this.blob.slice(entry.offset, entry.offset + 30).arrayBuffer());
        if (header.byteLength < 30 || header.getUint32(0, true) !== localSignature) {
            throw new ZipError(`The archive's entry ${path} is damaged.`);
        }
        // The local header's name and extra field can differ in length from
        // the directory's, so the data's start is read from it.
        const start = entry.offset + 30 + header.getUint16(26, true) + header.getUint16(28, true);
        const end = start + entry.compressedSize;
        if (end > this.blob.size) {
            throw new ZipError(`The archive's entry ${path} runs past its end.`);
        }
        const data = this.blob.slice(start, end);
        if (entry.method === 0) {
            return new Blob([data], { type });
        }
        if (entry.method !== 8) {
            throw new ZipError(`${path} uses a compression method the reader can't read.`);
        }
        const stream = data.stream().pipeThrough(new DecompressionStream("deflate-raw"));
        const chunks: Uint8Array[] = [];
        let total = 0;
        const reader = stream.getReader();
        for (;;) {
            const { done, value } = await reader.read();
            if (done) {
                break;
            }
            total += value.byteLength;
            // The directory's size can lie; the inflated bytes can't.
            if (total > this.limits.entrySize) {
                await reader.cancel();
                throw new ZipError(`${path} inflates past the limit of ${this.limits.entrySize} bytes.`);
            }
            chunks.push(value);
        }
        return new Blob(chunks as BlobPart[], { type });
    }

    async text(path: string): Promise<string> {
        return (await this.read(path)).text();
    }
}
