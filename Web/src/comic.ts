// Shows a comic's pages in an element: one page or a spread at a time, or
// every page in one scrolling column for webtoons. It owns layout, loading
// and input inside its element and nothing else: the app draws the
// controls around it, decides what a tap in the middle does, and saves
// the positions it reports.

import { type Locator, comicLocator, comicPageIndex } from "./locator.js";
import { nextScreen, previousScreen, screenPages, screenStart } from "./spreads.js";

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

interface Loaded {
    url: string;
    width: number;
    height: number;
    type: string;
}

const defaults: ComicOptions = { flow: "automatic", direction: "ltr", spreads: "automatic" };
// Pages kept decoded around the one on screen: enough to turn quickly
// either way without holding a whole volume of images.
const keepBehind = 4;
const keepAhead = 8;
const preloadAhead = 3;
const scrollKeep = 24;

let styled = false;

// Added as a constructed style sheet, which a content security policy
// without 'unsafe-inline' still allows, where a <style> element isn't.
function addStyles() {
    if (styled) return;
    styled = true;
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(`
.chek-comic { overflow: hidden; outline: none; touch-action: pan-y pinch-zoom; user-select: none; -webkit-user-select: none; }
.chek-comic[data-flow="scrolled"] { overflow-y: auto; overflow-x: hidden; touch-action: pan-x pan-y pinch-zoom; overscroll-behavior: contain; }
.chek-comic-stage { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; transform-origin: 0 0; }
.chek-comic[data-direction="rtl"] .chek-comic-stage { flex-direction: row-reverse; }
.chek-comic-stage > img { display: block; min-width: 0; max-height: 100%; object-fit: contain; -webkit-user-drag: none; }
.chek-comic-stage[data-pages="1"] > img { max-width: 100%; }
.chek-comic-stage[data-pages="2"] > img { max-width: 50%; }
.chek-comic-stage[data-pages="2"] > img:first-child { object-position: right; }
.chek-comic-stage[data-pages="2"] > img:last-child { object-position: left; }
.chek-comic[data-direction="rtl"] .chek-comic-stage[data-pages="2"] > img:first-child { object-position: left; }
.chek-comic[data-direction="rtl"] .chek-comic-stage[data-pages="2"] > img:last-child { object-position: right; }
.chek-comic-strip { display: flex; flex-direction: column; align-items: center; }
.chek-comic-strip > div { width: min(100%, var(--chek-comic-strip-width, 800px)); position: relative; }
.chek-comic-strip > div > img { display: block; width: 100%; height: 100%; -webkit-user-drag: none; }
.chek-comic-status { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; font: 500 15px/1.4 system-ui, sans-serif; opacity: 0.6; pointer-events: none; }
`);
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
}

/**
 * A comic's pages in `element`, which needs a size of its own, such as the
 * whole window, and a position other than static, since pages are laid
 * over it. Call `destroy` when it goes away.
 */
export class ComicView {
    private options: ComicOptions;
    private readonly pages = new Map<number, Promise<Loaded>>();
    private readonly loaded = new Map<number, Loaded>();
    private readonly controller = new AbortController();
    private start = 0;
    private flow: "paged" | "scrolled" = "paged";
    private stage?: HTMLDivElement;
    private strip?: HTMLDivElement;
    private observer?: IntersectionObserver;
    private resizer: ResizeObserver;
    private spreadsShown = false;
    private generation = 0;
    private zoom = { scale: 1, x: 0, y: 0 };
    private lastReported = -1;

    constructor(
        private readonly element: HTMLElement,
        private readonly source: PageSource,
        private readonly events: Partial<ComicEvents> = {},
        options: Partial<ComicOptions> = {},
        start: Locator | number | null = null,
    ) {
        addStyles();
        this.options = { ...defaults, ...options };
        const index =
            typeof start === "number"
                ? start
                : start && source.pageIndex
                  ? source.pageIndex(start)
                  : comicPageIndex(start, source.count);
        this.start = Math.min(Math.max(index ?? 0, 0), Math.max(source.count - 1, 0));
        element.classList.add("chek-comic");
        element.tabIndex = element.tabIndex >= 0 ? element.tabIndex : 0;
        this.listen();
        this.resizer = new ResizeObserver(() => this.relayout());
        this.resizer.observe(element);
        void this.setUp();
    }

    /** The first page on screen, from 0. */
    get page(): number {
        return this.start;
    }

    get count(): number {
        return this.source.count;
    }

    /** The flow in use, with `automatic` decided. */
    get currentFlow(): "paged" | "scrolled" {
        return this.flow;
    }

    /** Changes how pages are laid out, keeping the page on screen. */
    setOptions(options: Partial<ComicOptions>) {
        const before = this.options;
        this.options = { ...before, ...options };
        if (this.options.flow !== before.flow) {
            void this.setUp();
        } else {
            this.relayout(true);
        }
    }

    /** Shows the page at `index`, from 0. */
    goTo(index: number) {
        if (this.source.count === 0) return;
        const target = Math.min(Math.max(Math.round(index), 0), this.source.count - 1);
        if (this.flow === "scrolled") {
            this.strip?.children[target]?.scrollIntoView({ block: "start" });
            this.start = target;
            this.report();
        } else {
            this.show(screenStart(target, this.spreadsShown), 0);
        }
    }

    /** Shows the next page or spread. Returns false at the end. */
    next(): boolean {
        if (this.flow === "scrolled") return this.scrollBy(1);
        const next = nextScreen(this.start, this.source.count, this.spreadsShown);
        if (next === undefined) {
            this.events.end?.();
            return false;
        }
        this.show(next, 1);
        return true;
    }

    /** Shows the previous page or spread. Returns false at the start. */
    previous(): boolean {
        if (this.flow === "scrolled") return this.scrollBy(-1);
        const previous = previousScreen(this.start, this.spreadsShown);
        if (previous === undefined) return false;
        this.show(previous, -1);
        return true;
    }

    /**
     * Zooms in or out by `factor` around the middle of the view, such as
     * for a zoom key. Only paged comics zoom; reaching 1 shows the whole
     * page again.
     */
    zoomBy(factor: number) {
        if (this.flow !== "paged" || !this.stage) return;
        this.zoomTo(this.zoom.scale * factor, this.element.clientWidth / 2, this.element.clientHeight / 2);
    }

    /** The position of the first page on screen. */
    locator(): Locator {
        return (
            this.source.locator?.(this.start)
            ?? comicLocator(this.start, this.source.count, this.loaded.get(this.start)?.type)
        );
    }

    destroy() {
        this.controller.abort();
        this.resizer.disconnect();
        this.observer?.disconnect();
        for (const page of this.loaded.values()) URL.revokeObjectURL(page.url);
        this.loaded.clear();
        this.pages.clear();
        this.element.replaceChildren();
        this.element.classList.remove("chek-comic");
    }

    // MARK: - Loading

    private load(index: number): Promise<Loaded> {
        let pending = this.pages.get(index);
        if (pending) return pending;
        const signal = this.controller.signal;
        pending = (async () => {
            const blob = await this.source.load(index, signal);
            const url = URL.createObjectURL(blob);
            const image = new Image();
            image.src = url;
            try {
                await image.decode();
            } catch (error) {
                URL.revokeObjectURL(url);
                throw error;
            }
            if (signal.aborted) {
                URL.revokeObjectURL(url);
                throw signal.reason;
            }
            const page = { url, width: image.naturalWidth, height: image.naturalHeight, type: blob.type || "image/jpeg" };
            this.loaded.set(index, page);
            return page;
        })();
        // A failed page is forgotten, so showing it again retries.
        pending.catch((error: unknown) => {
            this.pages.delete(index);
            if (!signal.aborted) this.events.error?.(index, error);
        });
        this.pages.set(index, pending);
        return pending;
    }

    /** Lets go of decoded pages outside the window around `center`. */
    private trim(center: number, behind: number, ahead: number) {
        for (const [index, page] of this.loaded) {
            if (index < center - behind || index > center + ahead) {
                URL.revokeObjectURL(page.url);
                this.loaded.delete(index);
                this.pages.delete(index);
                if (this.flow === "scrolled") {
                    const image = this.strip?.children[index]?.querySelector("img");
                    image?.remove();
                }
            }
        }
    }

    // MARK: - Layout

    private async setUp() {
        const generation = ++this.generation;
        this.observer?.disconnect();
        this.element.replaceChildren();
        this.stage = undefined;
        this.strip = undefined;
        this.resetZoom();
        let flow = this.options.flow;
        if (flow === "automatic") flow = (await this.looksLikeWebtoon()) ? "scrolled" : "paged";
        if (generation !== this.generation) return;
        this.flow = flow;
        this.element.dataset.flow = flow;
        this.element.dataset.direction = this.options.direction;
        if (this.source.count === 0) {
            this.status("This comic has no pages.");
            return;
        }
        if (flow === "scrolled") {
            this.buildStrip();
        } else {
            this.spreadsShown = this.wantsSpreads();
            this.show(screenStart(this.start, this.spreadsShown), 0);
        }
    }

    // Webtoons are strips several times taller than they're wide. A few
    // pages after the cover, which is often an ordinary shape, decide.
    private async looksLikeWebtoon(): Promise<boolean> {
        const count = this.source.count;
        const sample = [1, 2, 3].filter((index) => index < count);
        if (sample.length === 0) return false;
        const sizes = await Promise.allSettled(sample.map((index) => this.load(index)));
        const tall = sizes.filter(
            (size) => size.status === "fulfilled" && size.value.height > size.value.width * 2,
        ).length;
        return tall * 2 > sample.length;
    }

    private wantsSpreads(): boolean {
        switch (this.options.spreads) {
            case "single":
                return false;
            case "double":
                return true;
            case "automatic":
                return this.element.clientWidth > this.element.clientHeight;
        }
    }

    private relayout(force = false) {
        this.element.dataset.direction = this.options.direction;
        if (this.flow !== "paged") return;
        const spreads = this.wantsSpreads();
        if (!force && spreads === this.spreadsShown) return;
        this.spreadsShown = spreads;
        this.show(screenStart(this.start, spreads), 0);
    }

    private status(text: string) {
        const status = document.createElement("p");
        status.className = "chek-comic-status";
        status.textContent = text;
        this.element.append(status);
    }

    // MARK: - Paged

    /** Shows the screen that starts at `start`. `motion` is 1 going forward, -1 back, 0 for a jump. */
    private show(start: number, motion: number) {
        this.start = start;
        this.resetZoom();
        const pages = screenPages(start, this.source.count, this.spreadsShown);
        const stage = document.createElement("div");
        stage.className = "chek-comic-stage";
        stage.dataset.pages = String(pages.length);
        const images = pages.map(() => {
            const image = document.createElement("img");
            image.alt = "";
            image.draggable = false;
            stage.append(image);
            return image;
        });
        const generation = this.generation;
        void Promise.all(pages.map((page) => this.load(page))).then(
            (loaded) => {
                if (generation !== this.generation || this.stage !== stage) return;
                loaded.forEach((page, index) => (images[index]!.src = page.url));
                this.report();
            },
            () => {
                if (generation !== this.generation || this.stage !== stage) return;
                stage.replaceChildren();
                const status = document.createElement("p");
                status.className = "chek-comic-status";
                status.textContent = "This page couldn't be loaded. Turn back and forth to try again.";
                stage.append(status);
            },
        );
        this.stage?.remove();
        this.stage = stage;
        this.element.append(stage);
        if (motion !== 0) this.slideIn(stage, motion);
        this.report();
        // The next few screens load while this one is read, so turning
        // shows them at once.
        let ahead: number | undefined = start;
        for (let step = 0; step < preloadAhead && ahead !== undefined; step++) {
            ahead = nextScreen(ahead, this.source.count, this.spreadsShown);
            if (ahead !== undefined) {
                for (const page of screenPages(ahead, this.source.count, this.spreadsShown)) {
                    this.load(page).catch(() => {});
                }
            }
        }
        const behind = previousScreen(start, this.spreadsShown);
        if (behind !== undefined) this.load(behind).catch(() => {});
        this.trim(start, keepBehind, keepAhead);
    }

    private slideIn(stage: HTMLElement, motion: number) {
        if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
        // Pages come in from the side the reader turns toward.
        const sign = (this.options.direction === "rtl" ? -1 : 1) * motion;
        stage.animate(
            [
                { transform: `translateX(${sign * 8}%)`, opacity: 0.4 },
                { transform: "translateX(0)", opacity: 1 },
            ],
            { duration: 180, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" },
        );
    }

    // MARK: - Scrolled

    private buildStrip() {
        const strip = document.createElement("div");
        strip.className = "chek-comic-strip";
        // Pages that haven't loaded take the shape of the last one that
        // has, so the column doesn't jump much as they arrive.
        let ratio = 1.5;
        for (let index = 0; index < this.source.count; index++) {
            const known = this.loaded.get(index);
            if (known) ratio = known.height / known.width;
            const slot = document.createElement("div");
            slot.dataset.page = String(index);
            slot.style.aspectRatio = `1 / ${known ? known.height / known.width : ratio}`;
            strip.append(slot);
        }
        this.strip = strip;
        this.element.append(strip);
        const generation = this.generation;
        this.observer = new IntersectionObserver(
            (entries) => {
                for (const entry of entries) {
                    if (!entry.isIntersecting) continue;
                    const slot = entry.target as HTMLDivElement;
                    const index = Number(slot.dataset.page);
                    if (slot.querySelector("img")) continue;
                    this.load(index).then(
                        (page) => {
                            if (generation !== this.generation || slot.querySelector("img")) return;
                            const image = document.createElement("img");
                            image.alt = "";
                            image.draggable = false;
                            image.src = page.url;
                            slot.style.aspectRatio = `${page.width} / ${page.height}`;
                            slot.append(image);
                        },
                        () => {},
                    );
                }
            },
            { root: this.element, rootMargin: "150% 0px" },
        );
        for (const slot of strip.children) this.observer.observe(slot);
        strip.children[this.start]?.scrollIntoView({ block: "start" });
        this.report();
    }

    private onScroll() {
        if (this.flow !== "scrolled" || !this.strip) return;
        // The page under the top third of the window is the one being read.
        const line = this.element.getBoundingClientRect().top + this.element.clientHeight / 3;
        const slots = this.strip.children;
        let low = 0;
        let high = slots.length - 1;
        while (low < high) {
            const middle = Math.ceil((low + high) / 2);
            if (slots[middle]!.getBoundingClientRect().top <= line) low = middle;
            else high = middle - 1;
        }
        if (low !== this.start) {
            this.start = low;
            this.trim(low, scrollKeep, scrollKeep);
            this.report();
        }
        const bottom = this.element.scrollTop + this.element.clientHeight;
        if (bottom >= this.element.scrollHeight - 2) this.report();
    }

    private scrollBy(direction: number): boolean {
        const before = this.element.scrollTop;
        const max = this.element.scrollHeight - this.element.clientHeight;
        if (direction > 0 && before >= max - 2) {
            this.events.end?.();
            return false;
        }
        if (direction < 0 && before <= 0) return false;
        this.element.scrollBy({ top: direction * this.element.clientHeight * 0.85, behavior: "smooth" });
        return true;
    }

    // MARK: - Reporting

    private report() {
        const count = this.source.count;
        const pages =
            this.flow === "scrolled" ? [this.start] : screenPages(this.start, count, this.spreadsShown);
        const last = pages[pages.length - 1] ?? 0;
        const atEnd =
            this.flow === "scrolled"
                ? this.element.scrollTop + this.element.clientHeight >= this.element.scrollHeight - 2
                : last >= count - 1;
        const key = this.start * 2 + (atEnd ? 1 : 0);
        if (key === this.lastReported) return;
        this.lastReported = key;
        this.events.location?.({ page: this.start, pages, count, locator: this.locator(), atEnd });
    }

    // MARK: - Zoom

    private resetZoom() {
        this.zoom = { scale: 1, x: 0, y: 0 };
        if (this.stage) this.stage.style.transform = "";
    }

    private applyZoom() {
        if (!this.stage) return;
        const { scale, x, y } = this.zoom;
        this.stage.style.transform = scale === 1 ? "" : `translate(${x}px, ${y}px) scale(${scale})`;
    }

    /** Zooms to `scale`, keeping the point at (`px`, `py`) in the element where it is. */
    private zoomTo(scale: number, px: number, py: number) {
        const { scale: before, x, y } = this.zoom;
        const clamped = Math.min(Math.max(scale, 1), 4);
        if (clamped === 1) {
            this.resetZoom();
            return;
        }
        const ratio = clamped / before;
        this.zoom = { scale: clamped, x: px - (px - x) * ratio, y: py - (py - y) * ratio };
        this.clampPan();
        this.applyZoom();
    }

    private clampPan() {
        const { scale } = this.zoom;
        const width = this.element.clientWidth;
        const height = this.element.clientHeight;
        this.zoom.x = Math.min(0, Math.max(width - width * scale, this.zoom.x));
        this.zoom.y = Math.min(0, Math.max(height - height * scale, this.zoom.y));
    }

    // MARK: - Input

    private listen() {
        const signal = this.controller.signal;
        const element = this.element;

        document.addEventListener(
            "keydown",
            (event) => {
                if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
                const target = event.target as HTMLElement | null;
                if (target?.closest("input, textarea, select, [contenteditable], [role=dialog], [role=slider]")) return;
                const rtl = this.options.direction === "rtl";
                const scrolled = this.flow === "scrolled";
                let handled = true;
                switch (event.key) {
                    case "ArrowRight":
                        if (scrolled) handled = false;
                        else if (rtl) this.previous();
                        else this.next();
                        break;
                    case "ArrowLeft":
                        if (scrolled) handled = false;
                        else if (rtl) this.next();
                        else this.previous();
                        break;
                    case "ArrowDown":
                    case "PageDown":
                        if (scrolled && event.key === "ArrowDown") handled = false;
                        else this.next();
                        break;
                    case "ArrowUp":
                    case "PageUp":
                        if (scrolled && event.key === "ArrowUp") handled = false;
                        else this.previous();
                        break;
                    case " ":
                        if (event.shiftKey) this.previous();
                        else this.next();
                        break;
                    case "Home":
                        this.goTo(0);
                        break;
                    case "End":
                        this.goTo(this.source.count - 1);
                        break;
                    default:
                        handled = false;
                }
                if (handled) event.preventDefault();
            },
            { signal },
        );

        // Taps and swipes, from one set of pointer events for mouse, pen
        // and touch alike.
        let down: { x: number; y: number; time: number; panX: number; panY: number } | undefined;
        let lastTap = 0;
        let tapTimer: ReturnType<typeof setTimeout> | undefined;
        element.addEventListener(
            "pointerdown",
            (event) => {
                if (event.button !== 0) return;
                down = { x: event.clientX, y: event.clientY, time: event.timeStamp, panX: this.zoom.x, panY: this.zoom.y };
                if (this.zoom.scale > 1) element.setPointerCapture(event.pointerId);
            },
            { signal },
        );
        element.addEventListener(
            "pointermove",
            (event) => {
                if (!down || this.zoom.scale === 1) return;
                this.zoom.x = down.panX + event.clientX - down.x;
                this.zoom.y = down.panY + event.clientY - down.y;
                this.clampPan();
                this.applyZoom();
            },
            { signal },
        );
        element.addEventListener(
            "pointerup",
            (event) => {
                if (!down) return;
                const dx = event.clientX - down.x;
                const dy = event.clientY - down.y;
                const quick = event.timeStamp - down.time < 600;
                down = undefined;
                if (this.zoom.scale > 1 && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) return;
                const rtl = this.options.direction === "rtl";
                if (this.flow === "paged" && this.zoom.scale === 1 && quick && Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.5) {
                    // Swiping toward the start of the line turns forward.
                    if (dx < 0 !== rtl) this.next();
                    else this.previous();
                    return;
                }
                if (Math.abs(dx) > 10 || Math.abs(dy) > 10) return;
                const rect = element.getBoundingClientRect();
                const x = event.clientX - rect.left;
                const y = event.clientY - rect.top;
                // A second tap soon after zooms in or out, in paged comics.
                if (this.flow === "paged" && event.timeStamp - lastTap < 300) {
                    clearTimeout(tapTimer);
                    lastTap = 0;
                    if (this.zoom.scale > 1) this.resetZoom();
                    else this.zoomTo(2.5, x, y);
                    return;
                }
                lastTap = event.timeStamp;
                const zone = x < rect.width * 0.3 ? "left" : x > rect.width * 0.7 ? "right" : "center";
                const act = () => {
                    if (zone === "center" || this.zoom.scale > 1) {
                        this.events.tap?.();
                    } else if (this.flow === "scrolled") {
                        this.scrollBy(zone === "right" ? 1 : -1);
                    } else if ((zone === "right") !== rtl) {
                        this.next();
                    } else {
                        this.previous();
                    }
                };
                // Waits a moment so a double tap doesn't also turn the page.
                if (this.flow === "paged") tapTimer = setTimeout(act, 220);
                else act();
            },
            { signal },
        );
        element.addEventListener("pointercancel", () => (down = undefined), { signal });

        // The wheel turns pages, one per gesture, and zooms with Control
        // or a trackpad pinch.
        let wheelLock = 0;
        element.addEventListener(
            "wheel",
            (event) => {
                if (this.flow === "scrolled" && !event.ctrlKey) return;
                event.preventDefault();
                if (event.ctrlKey) {
                    const rect = element.getBoundingClientRect();
                    this.zoomTo(this.zoom.scale * Math.exp(-event.deltaY / 100), event.clientX - rect.left, event.clientY - rect.top);
                    return;
                }
                if (this.zoom.scale > 1) {
                    this.zoom.x -= event.deltaX;
                    this.zoom.y -= event.deltaY;
                    this.clampPan();
                    this.applyZoom();
                    return;
                }
                const delta = Math.abs(event.deltaY) > Math.abs(event.deltaX) ? event.deltaY : event.deltaX;
                if (Math.abs(delta) < 4 || event.timeStamp < wheelLock) return;
                wheelLock = event.timeStamp + 350;
                if (delta > 0) this.next();
                else this.previous();
            },
            { signal, passive: false },
        );

        element.addEventListener("scroll", () => this.onScroll(), { signal, passive: true });
    }
}
