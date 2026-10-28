// A reflowable or fixed-layout book, such as an EPUB, drawn into an
// element you give it. Each resource of the reading order opens in a
// sandboxed frame that runs the Swift package's own pagination script,
// reader.js, so pages break the same way on every platform. The view keeps
// the resources either side loaded, turns pages within a resource and
// across them, and reports where the reader is as a Readium-compatible
// Locator.
//
// The element must be positioned by the app, as for comics. The frame is
// a page the app serves from its own origin; see the README's
// "Books" section for the files and the headers it needs.

import type { Publication, TocItem } from "./publication.js";
import { splitFragment } from "./href.js";
import type { Locator } from "./locator.js";
import { prepare } from "./prepare.js";

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

export const defaultBookPreferences: BookPreferences = {
    fontScale: 1,
    theme: "default",
    font: "default",
    lineHeight: 0,
    marginScale: 1,
};

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
    /** A turn past the last page. */
    end(): void;
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
}

interface PageState {
    page: number;
    pageCount: number;
    progression: number;
    generation: number;
}

type FrameMessage =
    | { type: "ready" }
    | { type: "reply"; id: number; result?: unknown; error?: string }
    | { type: "link"; href: string; external: boolean }
    | { type: "key"; key: string }
    | { type: "pointer" }
    | { type: "event"; message: { type: string; zone?: string; direction?: string; key?: string } & Partial<PageState> };

class Slot {
    readonly frame: HTMLIFrameElement;
    resource: number;
    state: PageState | undefined;
    ready: Promise<void>;
    /** Calls waiting for the frame's answer. */
    readonly replies = new Map<number, { resolve(value: unknown): void; reject(error: Error): void }>();
    loaded: () => void = () => {};

    constructor(container: HTMLElement, frameUrl: string, resource: number) {
        this.resource = resource;
        this.frame = document.createElement("iframe");
        // Scripts, for reader.js, in an origin of its own: no access to the
        // app, its storage or its cookies.
        this.frame.setAttribute("sandbox", "allow-scripts");
        this.frame.setAttribute("title", "Book page");
        this.frame.className = "chek-book-frame";
        this.frame.src = frameUrl;
        this.ready = new Promise((resolve) => {
            this.loaded = resolve;
        });
        container.appendChild(this.frame);
    }
}

// Two either side of the page on screen would be more than a turn needs.
const maximumSlots = 3;
// A frame that doesn't answer in this long has failed.
const callTimeout = 20_000;

const styles = `
.chek-book { overflow: hidden; outline: none; }
.chek-book-frame { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; visibility: hidden; background: transparent; }
.chek-book-frame[data-current] { visibility: visible; }
`;

let sheet: CSSStyleSheet | undefined;
function adoptStyles(root: Document | ShadowRoot) {
    // Constructed, not a <style> element, so a strict style-src allows it.
    sheet ??= (() => {
        const created = new CSSStyleSheet();
        created.replaceSync(styles);
        return created;
    })();
    if (!root.adoptedStyleSheets.includes(sheet)) {
        root.adoptedStyleSheets = [...root.adoptedStyleSheets, sheet];
    }
}

export class BookView {
    private readonly slots: Slot[] = [];
    private current: Slot | undefined;
    private nextId = 1;
    private generation = 0;
    private preferences: BookPreferences;
    private queue: Promise<unknown> = Promise.resolve();
    private readonly starts: number[] = [];
    private readonly positionCount: number;
    private destroyed = false;
    private lastLocation: BookLocation | undefined;

    constructor(
        private readonly element: HTMLElement,
        private readonly book: Publication,
        private readonly events: Partial<BookEvents>,
        private readonly options: BookOptions,
        start: Locator | null,
    ) {
        this.preferences = { ...options.preferences };
        let total = 0;
        for (const item of book.readingOrder) {
            this.starts.push(total);
            total += item.positions;
        }
        this.positionCount = total;
        adoptStyles(element.getRootNode() as Document | ShadowRoot);
        element.classList.add("chek-book");
        if (element.tabIndex < 0) {
            element.tabIndex = 0;
        }
        window.addEventListener("message", this.receive);
        // Keys turn pages wherever focus is on the page, such as on a
        // control just used, except in fields and dialogs.
        window.addEventListener("keydown", this.keydown);
        void this.enqueue(() => this.open(start));
    }

    /** Where the reader is, once the first page is on screen. */
    get location(): BookLocation | undefined {
        return this.lastLocation;
    }

    next(): Promise<void> {
        return this.enqueue(() => this.turn(1));
    }

    previous(): Promise<void> {
        return this.enqueue(() => this.turn(-1));
    }

    /** Goes to a place saved earlier, by its text when it has some, else its progression. */
    goTo(locator: Locator): Promise<void> {
        return this.enqueue(() => this.open(locator));
    }

    /** Goes to an href in the book, such as a table of contents entry's. */
    goToHref(href: string): Promise<void> {
        return this.enqueue(async () => {
            const [path, fragment] = splitFragment(href);
            const index = this.book.indexOf(path);
            if (index < 0) {
                return;
            }
            const slot = await this.load(index);
            const state = (fragment ? await this.call<PageState | null>(slot, "goToFragment", [fragment, this.generation]) : null)
                ?? await this.call<PageState>(slot, "goToPage", [0, this.generation]);
            await this.show(slot, state);
        });
    }

    /** The table of contents entry at a point through the whole book, from 0 to 1, such as for a slider's label. */
    chapterAt(total: number): TocItem | undefined {
        const href = this.book.readingOrder[this.resourceAt(total).index]?.href;
        return href === undefined ? undefined : this.chapterOf(href);
    }

    /** Goes to a point through the whole book, from 0 to 1. */
    goToProgression(total: number): Promise<void> {
        return this.enqueue(async () => {
            const { index, progression } = this.resourceAt(total);
            const slot = await this.load(index);
            await this.show(slot, await this.call<PageState>(slot, "goToProgression", [progression, this.generation]));
        });
    }

    setPreferences(preferences: Partial<BookPreferences>): Promise<void> {
        this.preferences = { ...this.preferences, ...preferences };
        this.generation += 1;
        return this.enqueue(async () => {
            // The page on screen first, and reported before the others:
            // a hidden frame can take seconds to lay a long chapter out
            // again, and the page count would show the old size until then.
            const current = this.current;
            const order = current ? [current, ...this.slots.filter((slot) => slot !== current)] : this.slots;
            for (const slot of order) {
                if (!slot.state) {
                    continue;
                }
                const state = await this.call<PageState>(slot, "setPreferences", [this.preferences, this.generation]).catch(() => undefined);
                if (state) {
                    slot.state = state;
                }
                if (slot === current) {
                    await this.report(slot);
                }
            }
        });
    }

    destroy(): void {
        this.destroyed = true;
        window.removeEventListener("message", this.receive);
        window.removeEventListener("keydown", this.keydown);
        for (const slot of this.slots) {
            slot.frame.remove();
            for (const reply of slot.replies.values()) {
                reply.reject(new Error("The book was closed."));
            }
        }
        this.slots.length = 0;
        this.element.classList.remove("chek-book");
    }

    // MARK: Opening and turning

    private enqueue<T>(work: () => Promise<T>): Promise<T> {
        const run = this.queue.then(() => (this.destroyed ? (undefined as T) : work()));
        // A failed step reports and lets the next one run.
        this.queue = run.catch((error: unknown) => {
            if (!this.destroyed) {
                this.events.error?.(error);
            }
        });
        return run;
    }

    private async open(locator: Locator | null): Promise<void> {
        const [path, fragment] = splitFragment(locator?.href ?? "");
        let index = this.book.indexOf(path);
        let progression = locator?.locations?.progression;
        if (index < 0) {
            // A locator from elsewhere may name the place only by how far through the book it is.
            const total = locator?.locations?.totalProgression;
            ({ index, progression } = total === undefined ? { index: 0, progression: 0 } : this.resourceAt(total));
        }
        const slot = await this.load(index);
        let state: PageState | null = null;
        const text = locator?.text;
        if (text?.highlight) {
            state = await this.call<PageState | null>(slot, "goToText", [text.highlight, text.before ?? "", this.generation, progression ?? 0]);
        }
        const fragments = [...(locator?.locations?.fragments ?? []), ...(fragment ? [fragment] : [])];
        if (!state && fragments[0] && progression === undefined) {
            state = await this.call<PageState | null>(slot, "goToFragment", [fragments[0], this.generation]);
        }
        state ??= await this.call<PageState>(slot, "goToProgression", [progression ?? 0, this.generation]);
        await this.show(slot, state);
    }

    private async turn(step: 1 | -1): Promise<void> {
        const slot = this.current;
        const state = slot?.state;
        if (!slot || !state) {
            return;
        }
        const page = state.page + step;
        if (page >= 0 && page < state.pageCount) {
            await this.show(slot, await this.call<PageState>(slot, "goToPage", [page, this.generation]));
            return;
        }
        const index = slot.resource + step;
        if (index < 0) {
            return;
        }
        if (index >= this.book.readingOrder.length) {
            this.events.end?.();
            return;
        }
        const next = await this.load(index);
        const method = step > 0 ? "goToPage" : "goToLastPage";
        const args = step > 0 ? [0, this.generation] : [this.generation];
        await this.show(next, await this.call<PageState>(next, method, args));
    }

    /** The resource and progression within it at a point through the whole book. */
    private resourceAt(total: number): { index: number; progression: number } {
        const position = Math.min(Math.max(total, 0), 1) * this.positionCount;
        let index = 0;
        while (index + 1 < this.starts.length && (this.starts[index + 1] ?? Infinity) <= position) {
            index += 1;
        }
        const count = this.book.readingOrder[index]?.positions ?? 1;
        return { index, progression: Math.min(Math.max((position - (this.starts[index] ?? 0)) / count, 0), 1) };
    }

    private async show(slot: Slot, state: PageState): Promise<void> {
        slot.state = state;
        if (this.current !== slot) {
            // Keys go to the focused frame, and one that's hidden would keep
            // them from the page on screen.
            if (this.current && document.activeElement === this.current.frame) {
                this.element.focus({ preventScroll: true });
            }
            this.current?.frame.removeAttribute("data-current");
            slot.frame.setAttribute("data-current", "");
            this.current = slot;
        }
        await this.report(slot);
        this.preload(slot.resource);
    }

    private preload(origin: number) {
        // The next resource first, since reading usually goes forward.
        const neighbors = [origin + 1, origin - 1].filter((index) => index >= 0 && index < this.book.readingOrder.length);
        void (async () => {
            for (const index of neighbors) {
                if (this.destroyed || this.current?.resource !== origin) {
                    return;
                }
                await this.load(index).catch(() => undefined);
            }
        })();
    }

    // MARK: Frames

    /** The slot holding `index`, loading the resource into one when none does. */
    private load(index: number): Promise<Slot> {
        const existing = this.slots.find((slot) => slot.resource === index);
        if (existing) {
            return existing.ready.then(() => {
                if (existing.resource !== index || !existing.state) {
                    throw new Error("This part of the book couldn't be opened.");
                }
                return existing;
            });
        }
        let slot: Slot;
        if (this.slots.length < maximumSlots) {
            slot = new Slot(this.element, this.options.frameUrl, index);
            this.slots.push(slot);
        } else {
            // The frame furthest from the one on screen, never that one.
            const center = this.current?.resource ?? index;
            slot = this.slots
                .filter((candidate) => candidate !== this.current)
                .reduce((far, candidate) => Math.abs(candidate.resource - center) > Math.abs(far.resource - center) ? candidate : far);
            slot.frame.remove();
            for (const reply of slot.replies.values()) {
                reply.reject(new Error("The frame was reused."));
            }
            const fresh = new Slot(this.element, this.options.frameUrl, index);
            this.slots[this.slots.indexOf(slot)] = fresh;
            slot = fresh;
        }
        const target = slot;
        const work = (async () => {
            await target.ready;
            const item = this.book.readingOrder[index];
            if (!item) {
                throw new Error("There's no such part of the book.");
            }
            const prepared = await prepare(this.book, item.href);
            await this.request(target, { chek: "load", markup: prepared.markup, xml: prepared.xml, resources: prepared.resources, fixed: item.fixed });
            // Preferences first, so the first layout already uses them.
            await this.call(target, "setPreferences", [this.preferences, this.generation]);
            target.state = await this.call<PageState>(target, "paginate", [{
                layout: item.fixed ? "fixed" : "reflowable",
                columns: 0,
                margin: 24,
                verticalMargin: 32,
                generation: this.generation,
            }]);
            return target;
        })();
        // Later loads of the same resource wait on this one.
        target.ready = work.then(() => {});
        return work;
    }

    private call<T>(slot: Slot, method: string, args: unknown[]): Promise<T> {
        return this.request(slot, { chek: "call", method, args }) as Promise<T>;
    }

    private request(slot: Slot, message: Record<string, unknown>): Promise<unknown> {
        const id = this.nextId++;
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                slot.replies.delete(id);
                reject(new Error("The book's page stopped answering."));
            }, callTimeout);
            slot.replies.set(id, {
                resolve: (value) => {
                    clearTimeout(timer);
                    resolve(value);
                },
                reject: (error) => {
                    clearTimeout(timer);
                    reject(error);
                },
            });
            slot.frame.contentWindow?.postMessage({ ...message, id }, "*");
        });
    }

    private readonly receive = (event: MessageEvent) => {
        const slot = this.slots.find((candidate) => candidate.frame.contentWindow === event.source);
        const data = event.data as ({ chekFrame?: boolean } & FrameMessage) | null;
        if (!slot || !data?.chekFrame) {
            return;
        }
        switch (data.type) {
            case "ready":
                slot.loaded();
                break;
            case "reply": {
                const reply = slot.replies.get(data.id);
                slot.replies.delete(data.id);
                if (data.error !== undefined) {
                    reply?.reject(new Error(data.error));
                } else {
                    reply?.resolve(data.result);
                }
                break;
            }
            case "link":
                if (slot === this.current) {
                    if (data.external) {
                        this.events.externalLink?.(data.href);
                    } else {
                        void this.goToHref(data.href);
                    }
                }
                break;
            case "key":
                // Focus can stay in a frame the reader has since hidden, and
                // the key is still the reader's.
                if (typeof data.key === "string") {
                    this.events.key?.(data.key);
                }
                break;
            case "pointer":
                if (slot === this.current) {
                    this.events.pointer?.();
                }
                break;
            case "event":
                this.input(slot, data.message);
                break;
        }
    };

    // MARK: Input

    private input(slot: Slot, message: { type: string; zone?: string; direction?: string; key?: string } & Partial<PageState>) {
        if (message.type === "layout") {
            // A resize or a late image moved the pages.
            if (typeof message.page === "number" && typeof message.pageCount === "number") {
                slot.state = { page: message.page, pageCount: message.pageCount, progression: message.progression ?? 0, generation: message.generation ?? 0 };
                if (slot === this.current) {
                    void this.enqueue(() => this.report(slot));
                }
            }
            return;
        }
        // Keys and the wheel turn the page on screen wherever they come
        // from: focus can stay in a frame the reader has since hidden.
        // Taps and swipes only come from the page on screen.
        if (slot !== this.current && message.type !== "key" && message.type !== "wheel") {
            return;
        }
        const rtl = this.book.metadata.readingProgression === "rtl";
        // Toward the left is forward in a right-to-left book.
        const leftward = rtl ? 1 : -1;
        let step: 1 | -1 | 0 = 0;
        switch (message.type) {
            case "tap":
                if (message.zone === "center") {
                    this.events.tap?.();
                    return;
                }
                step = message.zone === "left" ? leftward : (-leftward as 1 | -1);
                break;
            case "swipe":
                // Swiping toward the left reveals the page to the right.
                step = message.direction === "left" ? (-leftward as 1 | -1) : leftward;
                break;
            case "wheel":
                step = message.direction === "next" ? 1 : -1;
                break;
            case "key":
                step = this.keyStep(message.key ?? "");
                break;
        }
        if (step !== 0) {
            void this.enqueue(() => this.turn(step as 1 | -1));
        }
    }

    private keyStep(key: string): 1 | -1 | 0 {
        const rtl = this.book.metadata.readingProgression === "rtl";
        switch (key) {
            case "right":
                return rtl ? -1 : 1;
            case "left":
                return rtl ? 1 : -1;
            case "down":
            case "next":
                return 1;
            case "up":
            case "previous":
                return -1;
            default:
                return 0;
        }
    }

    private readonly keydown = (event: KeyboardEvent) => {
        const target = event.target instanceof Element ? event.target : null;
        if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey
            || target?.closest("input, textarea, select, [contenteditable], [role=dialog], [role=slider], [role=menu], [role=listbox]")
            // Space presses a focused button.
            || (event.key === " " && target?.closest("button, a"))) {
            return;
        }
        const keys: Record<string, string> = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down", PageDown: "next", PageUp: "previous", " ": event.shiftKey ? "previous" : "next" };
        const step = this.keyStep(keys[event.key] ?? "");
        if (step !== 0) {
            event.preventDefault();
            void this.enqueue(() => this.turn(step as 1 | -1));
        }
    };

    // MARK: Locations

    private async report(slot: Slot): Promise<void> {
        const state = slot.state;
        const item = this.book.readingOrder[slot.resource];
        if (!state || !item) {
            return;
        }
        const text = await this.call<{ before: string; highlight: string; after: string } | null>(slot, "locate", []).catch(() => null);
        const progression = state.pageCount > 0 ? state.page / state.pageCount : 0;
        const start = this.starts[slot.resource] ?? 0;
        const count = item.positions;
        const offset = Math.min(Math.floor(progression * count), count - 1);
        const atEnd = slot.resource === this.book.readingOrder.length - 1 && state.page >= state.pageCount - 1;
        const chapter = this.chapterOf(item.href);
        const locator: Locator = {
            href: item.href,
            type: item.type,
            ...(chapter ? { title: chapter.title } : {}),
            locations: {
                progression,
                position: start + offset + 1,
                // The server counts a book finished only at 1.
                totalProgression: atEnd ? 1 : (start + progression * count) / this.positionCount,
            },
            ...(text?.highlight ? { text } : {}),
        };
        this.lastLocation = {
            locator,
            resource: slot.resource,
            page: state.page,
            pageCount: state.pageCount,
            position: start + offset + 1,
            positionCount: this.positionCount,
            chapter,
            atStart: slot.resource === 0 && state.page === 0,
            atEnd,
        };
        this.events.location?.(this.lastLocation);
    }

    /** The deepest table of contents entry for a resource. */
    private chapterOf(href: string): TocItem | undefined {
        let found: TocItem | undefined;
        const visit = (items: TocItem[]) => {
            for (const item of items) {
                if (splitFragment(item.href)[0] === href && !found) {
                    found = item;
                }
                visit(item.children);
            }
        };
        visit(this.book.toc);
        if (found) {
            return found;
        }
        // A resource with no entry of its own belongs to the entry before it.
        const index = this.book.indexOf(href);
        for (let before = index - 1; before >= 0; before -= 1) {
            const path = this.book.readingOrder[before]?.href;
            const entry = path ? this.flatToc().find((item) => splitFragment(item.href)[0] === path) : undefined;
            if (entry) {
                return entry;
            }
        }
        return undefined;
    }

    private flatToc(): TocItem[] {
        const flat: TocItem[] = [];
        const visit = (items: TocItem[]) => {
            for (const item of items) {
                flat.push(item);
                visit(item.children);
            }
        };
        visit(this.book.toc);
        return flat;
    }
}
