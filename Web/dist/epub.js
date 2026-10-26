// Opens an EPUB 2 or 3 from its file: the package document's metadata and
// reading order, and the table of contents from the navigation document
// or, for EPUB 2, the NCX. Resources are read from the archive on demand.
import { resolveHref } from "./href.js";
import { ZipArchive } from "./zip.js";
/** The publication is protected by DRM, which the reader doesn't decrypt. */
export class DrmError extends Error {
}
/** The file isn't an EPUB the reader can open. */
export class EpubError extends Error {
}
/** An opened EPUB. */
export class Epub {
    archive;
    metadata;
    readingOrder;
    toc;
    types;
    constructor(archive, metadata, readingOrder, toc, types) {
        this.archive = archive;
        this.metadata = metadata;
        this.readingOrder = readingOrder;
        this.toc = toc;
        this.types = types;
    }
    static async open(file, limits) {
        const archive = await ZipArchive.open(file, limits);
        const xml = async (path) => {
            const document = new DOMParser().parseFromString(await archive.text(path), "application/xml");
            if (document.getElementsByTagName("parsererror").length > 0) {
                throw new EpubError(`${path} isn't well-formed XML.`);
            }
            return document;
        };
        if (!archive.has("META-INF/container.xml")) {
            throw new EpubError("This file has no META-INF/container.xml, so it isn't an EPUB.");
        }
        if (archive.has("META-INF/encryption.xml")) {
            checkEncryption(await xml("META-INF/encryption.xml"), archive);
        }
        const container = await xml("META-INF/container.xml");
        const packagePath = first(container, "rootfile")?.getAttribute("full-path");
        if (!packagePath || !archive.has(packagePath)) {
            throw new EpubError("The EPUB's container doesn't name a package document it holds.");
        }
        const opf = await xml(packagePath);
        const types = new Map();
        const items = new Map();
        for (const item of all(opf, "item")) {
            const id = item.getAttribute("id");
            const path = resolveHref(item.getAttribute("href") ?? "", packagePath);
            if (!id || !path) {
                continue;
            }
            const type = item.getAttribute("media-type") ?? "";
            types.set(path, type);
            items.set(id, { path, type, properties: words(item.getAttribute("properties")) });
        }
        const fixedByDefault = all(opf, "meta").some((meta) => meta.getAttribute("property") === "rendition:layout" && meta.textContent?.trim() === "pre-paginated");
        const spine = first(opf, "spine");
        const readingOrder = [];
        const seen = new Set();
        for (const itemref of all(opf, "itemref")) {
            if (itemref.getAttribute("linear") === "no") {
                continue;
            }
            const item = items.get(itemref.getAttribute("idref") ?? "");
            if (!item || !archive.has(item.path) || seen.has(item.path)) {
                continue;
            }
            seen.add(item.path);
            const properties = words(itemref.getAttribute("properties"));
            const fixed = properties.includes("rendition:layout-pre-paginated")
                || (fixedByDefault && !properties.includes("rendition:layout-reflowable"));
            const size = archive.size(item.path) ?? 0;
            readingOrder.push({
                href: item.path,
                type: item.type || "application/xhtml+xml",
                fixed,
                positions: fixed ? 1 : Math.min(Math.max(1, Math.ceil(size / 1024)), 1 << 24),
            });
        }
        if (readingOrder.length === 0) {
            throw new EpubError("The EPUB's spine lists nothing to read.");
        }
        const metadata = {
            title: first(opf, "title")?.textContent?.trim() || "",
            authors: all(opf, "creator")
                .filter((creator) => {
                const role = creator.getAttribute("opf:role") ?? creator.getAttributeNS("*", "role");
                return !role || role === "aut";
            })
                .map((creator) => creator.textContent?.trim() ?? "")
                .filter(Boolean),
            language: first(opf, "language")?.textContent?.trim() || null,
            readingProgression: spine?.getAttribute("page-progression-direction") === "rtl" ? "rtl" : "ltr",
        };
        let toc = [];
        const nav = [...items.values()].find((item) => item.properties.includes("nav"));
        if (nav && archive.has(nav.path)) {
            toc = navToc(await xml(nav.path), nav.path);
        }
        const ncxId = spine?.getAttribute("toc");
        const ncx = ncxId ? items.get(ncxId) : [...items.values()].find((item) => item.type === "application/x-dtbncx+xml");
        if (toc.length === 0 && ncx && archive.has(ncx.path)) {
            toc = ncxToc(await xml(ncx.path), ncx.path);
        }
        return new Epub(archive, metadata, readingOrder, toc, types);
    }
    /** A resource's bytes, by its path from the publication's root. */
    resource(path) {
        return this.archive.read(path, this.types.get(path) ?? mediaTypeFor(path));
    }
    has(path) {
        return this.archive.has(path);
    }
    /** A resource's media type, from the manifest or its extension. */
    typeOf(path) {
        return this.types.get(path) ?? mediaTypeFor(path);
    }
    /** The index of a resource in the reading order, or -1. */
    indexOf(path) {
        return this.readingOrder.findIndex((item) => item.href === path);
    }
    /** How many positions the whole publication holds. */
    get positionCount() {
        return this.readingOrder.reduce((sum, item) => sum + item.positions, 0);
    }
}
function first(document, name) {
    return document.getElementsByTagNameNS("*", name)[0] ?? undefined;
}
function all(document, name) {
    return Array.from(document.getElementsByTagNameNS("*", name));
}
function words(value) {
    return (value ?? "").split(/\s+/).filter(Boolean);
}
// IDPF and Adobe font obfuscation only scrambles fonts; anything else
// encrypted is DRM.
const fontObfuscation = new Set([
    "http://www.idpf.org/2008/embedding",
    "http://ns.adobe.com/pdf/enc#RC",
]);
function checkEncryption(document, archive) {
    for (const data of all(document, "EncryptedData")) {
        const algorithm = first(data, "EncryptionMethod")?.getAttribute("Algorithm") ?? "";
        if (fontObfuscation.has(algorithm)) {
            continue;
        }
        const scheme = archive.has("META-INF/rights.xml")
            ? "Adobe DRM"
            : archive.has("META-INF/license.lcpl")
                ? "Readium LCP"
                : "DRM";
        throw new DrmError(`This book is protected by ${scheme}, which Chek Reader doesn't open.`);
    }
}
function navToc(document, base) {
    const navs = all(document, "nav");
    const toc = navs.find((nav) => words(nav.getAttributeNS("http://www.idpf.org/2007/ops", "type") ?? nav.getAttribute("epub:type")).includes("toc"))
        ?? navs[0];
    const list = toc && Array.from(toc.children).find((child) => child.localName === "ol");
    return list ? navList(list, base) : [];
}
function navList(list, base) {
    const items = [];
    for (const li of Array.from(list.children).filter((child) => child.localName === "li")) {
        const label = Array.from(li.children).find((child) => child.localName === "a" || child.localName === "span");
        const nested = Array.from(li.children).find((child) => child.localName === "ol");
        const href = label?.localName === "a" ? resolveHref(label.getAttribute("href") ?? "", base) : null;
        const children = nested ? navList(nested, base) : [];
        const title = label?.textContent?.replace(/\s+/g, " ").trim() ?? "";
        if (href && title) {
            items.push({ title, href, children });
        }
        else {
            // A heading with no link of its own groups its children.
            items.push(...children);
        }
    }
    return items;
}
function ncxToc(document, base) {
    const map = first(document, "navMap");
    return map ? ncxPoints(map, base) : [];
}
function ncxPoints(parent, base) {
    const items = [];
    for (const point of Array.from(parent.children).filter((child) => child.localName === "navPoint")) {
        const title = first(point, "text")?.textContent?.replace(/\s+/g, " ").trim() ?? "";
        const src = Array.from(point.children).find((child) => child.localName === "content")?.getAttribute("src") ?? "";
        const href = resolveHref(src, base);
        const children = ncxPoints(point, base);
        if (href && title) {
            items.push({ title, href, children });
        }
        else {
            items.push(...children);
        }
    }
    return items;
}
const extensionTypes = {
    xhtml: "application/xhtml+xml",
    html: "text/html",
    htm: "text/html",
    css: "text/css",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
    otf: "font/otf",
    ttf: "font/ttf",
    woff: "font/woff",
    woff2: "font/woff2",
    mp3: "audio/mpeg",
    mp4: "video/mp4",
};
function mediaTypeFor(path) {
    return extensionTypes[path.split(".").pop()?.toLowerCase() ?? ""] ?? "application/octet-stream";
}
