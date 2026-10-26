// PDF for the web, an optional entry, `@readchek/reader/pdf`, since it's
// the one part of the package with a dependency: Mozilla's pdf.js. Apps
// that never open a PDF never load it.
//
// A PDF reads in `ComicView`, a page at a time or in spreads, zoomed with a
// pinch or a double-click, with each page drawn by pdf.js at the size the
// screen needs. Its locators match the Swift package's: the one resource
// `publication.pdf`, with a `page=N` fragment counting from 1.
import { GlobalWorkerOptions, getDocument } from "pdfjs-dist";
import { pdfHref, pdfLocator, pdfPageIndex } from "./locator.js";
/** The PDF can't be opened, such as when it's damaged or needs a password. */
export class PdfError extends Error {
}
// Pages are drawn about as tall as the screen in device pixels, within
// these bounds, so they stay sharp without holding huge images.
const minHeight = 1400;
const maxHeight = 3000;
/** An opened PDF: its pages for `ComicView`, its outline and its title. */
export class PdfDocument {
    document;
    title;
    toc;
    sections;
    constructor(document, 
    /** The title from the PDF's information, or an empty string. */
    title, 
    /** The outline, with hrefs such as `publication.pdf#page=3`. */
    toc, 
    /** For each outline entry with a page, the page from 0, in page order. */
    sections) {
        this.document = document;
        this.title = title;
        this.toc = toc;
        this.sections = sections;
    }
    static async open(file, files) {
        GlobalWorkerOptions.workerSrc = files.worker;
        let document;
        try {
            document = await getDocument({
                data: new Uint8Array(await file.arrayBuffer()),
                cMapUrl: files.cMaps,
                cMapPacked: true,
                standardFontDataUrl: files.standardFonts,
            }).promise;
        }
        catch (error) {
            const name = error instanceof Error ? error.name : "";
            throw new PdfError(name === "PasswordException"
                ? "This PDF needs a password, which the reader doesn't ask for yet."
                : `This file isn't a PDF the reader can open: ${error instanceof Error ? error.message : String(error)}`, { cause: error });
        }
        const info = await document.getMetadata().catch(() => undefined);
        const title = info?.info?.Title;
        const sections = [];
        const toc = await outline(document, sections).catch(() => []);
        sections.sort((a, b) => a.page - b.page);
        return new PdfDocument(document, typeof title === "string" ? title.trim() : "", toc, sections);
    }
    get count() {
        return this.document.numPages;
    }
    /** The outline entry a page is in, as the Swift package titles its locators. */
    sectionTitle(index) {
        let title;
        for (const section of this.sections) {
            if (section.page > index)
                break;
            title = section.title;
        }
        return title;
    }
    async load(index, signal) {
        const page = await this.document.getPage(index + 1);
        const natural = page.getViewport({ scale: 1 });
        const screenHeight = (globalThis.screen?.height ?? 1000) * (globalThis.devicePixelRatio ?? 1);
        const height = Math.min(Math.max(screenHeight, minHeight), maxHeight);
        const viewport = page.getViewport({ scale: height / natural.height });
        const canvas = document.createElement("canvas");
        canvas.width = Math.ceil(viewport.width);
        canvas.height = Math.ceil(viewport.height);
        const task = page.render({ canvas, viewport });
        const cancel = () => task.cancel();
        signal.addEventListener("abort", cancel, { once: true });
        try {
            await task.promise;
        }
        finally {
            signal.removeEventListener("abort", cancel);
            page.cleanup();
        }
        const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
        // The canvas's memory is freed now rather than when it's collected.
        canvas.width = 0;
        canvas.height = 0;
        if (!blob)
            throw new PdfError(`Page ${index + 1} couldn't be drawn.`);
        return blob;
    }
    locator(index) {
        return pdfLocator(index, this.count, this.sectionTitle(index));
    }
    pageIndex(locator) {
        return pdfPageIndex(locator, this.count);
    }
    /** Frees pdf.js's copy of the file and its worker. */
    destroy() {
        return this.document.loadingTask.destroy();
    }
}
// The PDF's outline as contents. Entries that point at no page, such as
// links to the web, keep their place for their children but have no href
// of their own, so they lead to their first child's page.
async function outline(document, sections) {
    const nodes = (await document.getOutline()) ?? [];
    const pageOf = async (node) => {
        try {
            const destination = typeof node.dest === "string" ? await document.getDestination(node.dest) : node.dest;
            const target = destination?.[0];
            if (target === undefined || target === null)
                return undefined;
            return typeof target === "number" ? target : await document.getPageIndex(target);
        }
        catch {
            return undefined;
        }
    };
    const convert = async (list, depth) => {
        const items = [];
        for (const node of list) {
            const page = await pageOf(node);
            const title = node.title.trim();
            const children = depth < 8 ? await convert(node.items ?? [], depth + 1) : [];
            const href = page === undefined ? children[0]?.href : `${pdfHref}#page=${page + 1}`;
            if (page !== undefined && title)
                sections.push({ page, title });
            if (href && title)
                items.push({ title, href, children });
            else
                items.push(...children);
        }
        return items;
    };
    return convert(nodes, 0);
}
