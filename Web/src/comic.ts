// Shows a comic's pages in an element: one page or a spread at a time, or
// every page in one scrolling column for webtoons. It owns layout, loading
// and input inside its element and nothing else: the app draws the
// controls around it, decides what a tap in the middle does, and saves
// the positions it reports.

import { type Edge, looksLikeStrip, turn } from "./flow.js";
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
.chek-comic-strip > div[data-page] { width: min(100%, var(--chek-comic-strip-width, 800px)); position: relative; }
.chek-comic-strip > div[data-page] > img { display: block; width: 100%; height: 100%; -webkit-user-drag: none; }
.chek-comic-strip > .chek-comic-edge { width: 100%; }
.chek-comic-stage > .chek-comic-edge { width: 100%; height: 100%; }
.chek-comic-edge { user-select: text; -webkit-user-select: text; }
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
    /** The end a paged comic has turned onto, in place of pages. */
    private edge: Edge | null = null;
    /** The scrolled column's pages, in order, without what's above and below them. */
    private slots: HTMLDivElement[] = [];
    private readonly ends: { before?: HTMLDivElement; after?: HTMLDivElement } = {};
    private lastLeft = 0;
    /** Whether it opened at its end, read back into from what follows it. */
    private fromEnd = false;
    /**
     * Where a scrolled column was opened, held there while pages above
     * load and take their real heights, until the reader moves it.
     */
    private opened: { slot: HTMLDivElement; block: "start" | "end" } | null = null;

    constructor(
        private readonly element: HTMLElement,
        private readonly source: PageSource,
        private readonly events: Partial<ComicEvents> = {},
        options: Partial<ComicOptions> = {},
        start: Locator | number | "end" | null = null,
        ends: ComicEnds = {},
    ) {
        addStyles();
        for (const edge of ["before", "after"] as const) {
            const content = ends[edge];
            if (!content) continue;
            const holder = document.createElement("div");
            holder.className = "chek-comic-edge";
            holder.dataset.edge = edge;
            holder.append(content);
            this.ends[edge] = holder;
        }
        this.options = { ...defaults, ...options };
        this.fromEnd = start === "end";
        const index =
            start === "end"
                ? source.count - 1
                : typeof start === "number"
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
            this.opened = null;
            this.slots[target]?.scrollIntoView({ block: "start" });
            this.start = target;
            this.report();
        } else {
            this.show(screenStart(target, this.spreadsShown), 0);
        }
    }

    /** Whether something shows before the first page or after the last. */
    private get edges() {
        return { before: this.ends.before !== undefined, after: this.ends.after !== undefined };
    }

    private turnPaged(direction: 1 | -1): boolean {
        const count = this.source.count;
        const result = turn(
            { start: this.start, edge: this.edge },
            direction,
            {
                next: nextScreen(this.start, count, this.spreadsShown),
                previous: previousScreen(this.start, this.spreadsShown),
                first: 0,
                last: screenStart(Math.max(count - 1, 0), this.spreadsShown),
            },
            this.edges,
        );
        switch (result.kind) {
            case "pages":
                this.show(result.start, direction);
                return true;
            case "edge":
                this.showEdge(result.edge, direction);
                return true;
            case "leave":
                this.leave(result.toward);
                return false;
            case "stay":
                if (direction === 1) this.events.end?.();
                return false;
        }
    }

    /** Whether a key is held down, repeating. Holding one turns pages but never leaves them. */
    private held = false;

    private leave(toward: Edge) {
        if (this.held) return;
        // One gesture can arrive as several events; it leaves once.
        const now = performance.now();
        if (now - this.lastLeft < 600) return;
        this.lastLeft = now;
        this.events.leave?.(toward);
    }

    /** Shows the next page or spread. Returns false at the end. */
    next(): boolean {
        if (this.flow === "scrolled") return this.scrollBy(1);
        return this.turnPaged(1);
    }

    /** Shows the previous page or spread. Returns false at the start. */
    previous(): boolean {
        if (this.flow === "scrolled") return this.scrollBy(-1);
        return this.turnPaged(-1);
    }

    /**
     * Zooms in or out by `factor` around the middle of the view, such as
     * for a zoom key. Only paged comics zoom; reaching 1 shows the whole
     * page again.
     */
    zoomBy(factor: number) {
        if (this.flow !== "paged" || !this.stage || this.edge) return;
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
                    const image = this.slots[index]?.querySelector("img");
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
        this.slots = [];
        this.edge = null;
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

    // A few pages after the cover, which is often an ordinary shape even
    // in a webtoon, decide. See `looksLikeStrip` for what they're asked.
    private async looksLikeWebtoon(): Promise<boolean> {
        const count = this.source.count;
        const sample = [1, 2, 3, 4, 5].filter((index) => index < count);
        if (sample.length === 0) return false;
        const sizes = await Promise.allSettled(sample.map((index) => this.load(index)));
        return looksLikeStrip(sizes.flatMap((size) => (size.status === "fulfilled" ? [size.value] : [])));
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
        // An end stays up through a resize; the pages regroup under it.
        if (this.edge) this.start = screenStart(this.start, spreads);
        else this.show(screenStart(this.start, spreads), 0);
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
        this.edge = null;
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

    /** Shows what's before the first page or after the last, as a screen of its own. */
    private showEdge(edge: Edge, motion: number) {
        const holder = this.ends[edge];
        if (!holder) return;
        this.edge = edge;
        this.start = edge === "after" ? screenStart(Math.max(this.source.count - 1, 0), this.spreadsShown) : 0;
        this.resetZoom();
        const stage = document.createElement("div");
        stage.className = "chek-comic-stage";
        stage.dataset.edge = edge;
        stage.append(holder);
        this.stage?.remove();
        this.stage = stage;
        this.element.append(stage);
        if (motion !== 0) this.slideIn(stage, motion);
        this.report();
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
            this.slots.push(slot);
        }
        // What's before and after the pages scrolls with them, above the
        // first and below the last.
        if (this.ends.before) strip.prepend(this.ends.before);
        if (this.ends.after) strip.append(this.ends.after);
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
                            this.opened?.slot.scrollIntoView({ block: this.opened.block });
                        },
                        () => {},
                    );
                }
            },
            { root: this.element, rootMargin: "150% 0px" },
        );
        for (const slot of this.slots) this.observer.observe(slot);
        // Read back into, a column shows the foot of its last page, as it was left.
        const slot = this.slots[this.start];
        this.opened = slot ? { slot, block: this.fromEnd ? "end" : "start" } : null;
        this.fromEnd = false;
        slot?.scrollIntoView({ block: this.opened?.block });
        this.report();
    }

    private onScroll() {
        if (this.flow !== "scrolled" || !this.strip) return;
        // The page under the top third of the window is the one being read.
        const line = this.element.getBoundingClientRect().top + this.element.clientHeight / 3;
        const slots = this.slots;
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
        this.report();
    }

    /** Whether the column is scrolled as far as it goes, down (1) or up (-1). */
    private scrolledToEnd(direction: number): boolean {
        if (direction > 0) {
            return this.element.scrollTop >= this.element.scrollHeight - this.element.clientHeight - 2;
        }
        return this.element.scrollTop <= 0;
    }

    private scrollBy(direction: number): boolean {
        if (this.scrolledToEnd(direction)) {
            const toward: Edge = direction > 0 ? "after" : "before";
            if (this.ends[toward]) this.leave(toward);
            else if (direction > 0) this.events.end?.();
            return false;
        }
        this.element.scrollBy({ top: direction * this.element.clientHeight * 0.85, behavior: "smooth" });
        return true;
    }

    // MARK: - Reporting

    private report() {
        const count = this.source.count;
        const pages =
            this.flow === "scrolled" ? [this.start] : screenPages(this.start, count, this.spreadsShown);
        const last = pages[pages.length - 1] ?? 0;
        const view = this.element.getBoundingClientRect();
        // A scrolled comic has reached its end once the foot of its last
        // page is in view, which is where what's after it begins.
        const lastSlot = this.slots[this.slots.length - 1];
        const atEnd =
            this.flow === "scrolled"
                ? this.scrolledToEnd(1)
                  || (lastSlot !== undefined && lastSlot.getBoundingClientRect().bottom <= view.bottom + 2)
                : this.edge !== "before" && last >= count - 1;
        const key = (this.start * 2 + (atEnd ? 1 : 0)) * 3 + (this.edge === "after" ? 1 : this.edge === "before" ? 2 : 0);
        if (key === this.lastReported) return;
        this.lastReported = key;
        this.events.location?.({ page: this.start, pages, count, locator: this.locator(), atEnd, edge: this.edge });
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
                // Space presses a focused button, such as an app's page turn button.
                if (event.key === " " && target?.closest("button, a")) return;
                const rtl = this.options.direction === "rtl";
                const scrolled = this.flow === "scrolled";
                let handled = true;
                this.held = event.repeat;
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
                        // The browser scrolls for the arrow, until there's nothing left to scroll.
                        if (scrolled && event.key === "ArrowDown" && !this.scrolledToEnd(1)) handled = false;
                        else this.next();
                        break;
                    case "ArrowUp":
                    case "PageUp":
                        if (scrolled && event.key === "ArrowUp" && !this.scrolledToEnd(-1)) handled = false;
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
                this.held = false;
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
                // What an app puts in an end, such as a link, takes its own clicks.
                if ((event.target as Element | null)?.closest?.("a, button, input, select, textarea, [role=button]")) return;
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
                const zone = x < rect.width * 0.3 ? "left" : x > rect.width * 0.7 ? "right" : "center";
                const turns = zone !== "center" && this.zoom.scale === 1;
                // A second tap soon after zooms in or out, in paged comics.
                // Only where a tap doesn't turn the page, so a turn never
                // has to wait to learn whether a second tap is coming.
                if (this.flow === "paged" && !this.edge && !turns && event.timeStamp - lastTap < 300) {
                    clearTimeout(tapTimer);
                    lastTap = 0;
                    if (this.zoom.scale > 1) this.resetZoom();
                    else this.zoomTo(2.5, x, y);
                    return;
                }
                lastTap = turns ? 0 : event.timeStamp;
                // A turn can put an end's page under the finger. The click
                // that follows the tap belongs to the page turned from.
                if (turns) swallowClick = event.timeStamp + 500;
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
                if (this.flow === "paged" && !turns && !this.edge) tapTimer = setTimeout(act, 220);
                else act();
            },
            { signal },
        );
        element.addEventListener("pointercancel", () => (down = undefined), { signal });
        let swallowClick = 0;
        element.addEventListener(
            "click",
            (event) => {
                if (event.timeStamp > swallowClick) return;
                swallowClick = 0;
                event.preventDefault();
                event.stopPropagation();
            },
            { signal, capture: true },
        );

        // The wheel turns pages, one per gesture, and zooms with Control
        // or a trackpad pinch.
        let wheelLock = 0;
        // Wheels and trackpads keep sending events as a scroll coasts to a
        // stop. Leaving the pages takes a push that starts after the last
        // one has come to rest, so coasting into an end never goes through it.
        let lastWheel = 0;
        let armed = false;
        let pushed = 0;
        element.addEventListener(
            "wheel",
            (event) => {
                const fresh = event.timeStamp - lastWheel > 180;
                lastWheel = event.timeStamp;
                if (this.flow === "scrolled" && !event.ctrlKey) {
                    const direction = Math.sign(event.deltaY);
                    if (direction === 0 || !this.scrolledToEnd(direction)) {
                        armed = false;
                        pushed = 0;
                        return;
                    }
                    if (fresh) armed = true;
                    if (!armed) return;
                    // More than one notch of a mouse wheel, so a last nudge
                    // to see the foot of the page doesn't go through it.
                    pushed += Math.abs(event.deltaY);
                    if (pushed >= 150) {
                        armed = false;
                        pushed = 0;
                        this.scrollBy(direction);
                    }
                    return;
                }
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
                // On an end, the turn that leaves it is a push of its own.
                if (this.edge && !fresh) return;
                wheelLock = event.timeStamp + 350;
                if (delta > 0) this.next();
                else this.previous();
            },
            { signal, passive: false },
        );

        element.addEventListener("scroll", () => this.onScroll(), { signal, passive: true });
        for (const moved of ["wheel", "touchstart", "pointerdown", "keydown"]) {
            element.addEventListener(moved, () => (this.opened = null), { signal, passive: true, capture: true });
        }

        // A finger pulling a scrolled comic on past its end, or back past
        // its start, leaves through that end. The browser takes over a
        // touch that scrolls, so pointer events never see it through.
        let pull: { y: number; atTop: boolean; atBottom: boolean } | undefined;
        element.addEventListener(
            "touchstart",
            (event) => {
                pull =
                    this.flow === "scrolled" && event.touches.length === 1
                        ? { y: event.touches[0]!.clientY, atTop: this.scrolledToEnd(-1), atBottom: this.scrolledToEnd(1) }
                        : undefined;
            },
            { signal, passive: true },
        );
        element.addEventListener(
            "touchend",
            (event) => {
                const start = pull;
                pull = undefined;
                const touch = event.changedTouches[0];
                if (!start || !touch) return;
                const moved = touch.clientY - start.y;
                if (start.atBottom && moved < -70 && this.scrolledToEnd(1)) this.scrollBy(1);
                else if (start.atTop && moved > 70 && this.scrolledToEnd(-1)) this.scrollBy(-1);
            },
            { signal, passive: true },
        );
    }
}
