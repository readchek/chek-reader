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
import { splitFragment } from "./href.js";
import { prepare } from "./prepare.js";
export const defaultBookPreferences = {
    fontScale: 1,
    theme: "default",
    font: "default",
    lineHeight: 0,
    marginScale: 1,
};
class Slot {
    frame;
    resource;
    state;
    ready;
    /** Calls waiting for the frame's answer. */
    replies = new Map();
    loaded = () => { };
    constructor(container, frameUrl, resource) {
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
let sheet;
function adoptStyles(root) {
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
    element;
    book;
    events;
    options;
    slots = [];
    current;
    nextId = 1;
    generation = 0;
    preferences;
    queue = Promise.resolve();
    starts = [];
    positionCount;
    destroyed = false;
    lastLocation;
    constructor(element, book, events, options, start) {
        this.element = element;
        this.book = book;
        this.events = events;
        this.options = options;
        this.preferences = { ...options.preferences };
        let total = 0;
        for (const item of book.readingOrder) {
            this.starts.push(total);
            total += item.positions;
        }
        this.positionCount = total;
        adoptStyles(element.getRootNode());
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
    get location() {
        return this.lastLocation;
    }
    next() {
        return this.enqueue(() => this.turn(1));
    }
    previous() {
        return this.enqueue(() => this.turn(-1));
    }
    /** Goes to a place saved earlier, by its text when it has some, else its progression. */
    goTo(locator) {
        return this.enqueue(() => this.open(locator));
    }
    /** Goes to an href in the book, such as a table of contents entry's. */
    goToHref(href) {
        return this.enqueue(async () => {
            const [path, fragment] = splitFragment(href);
            const index = this.book.indexOf(path);
            if (index < 0) {
                return;
            }
            const slot = await this.load(index);
            const state = (fragment ? await this.call(slot, "goToFragment", [fragment, this.generation]) : null)
                ?? await this.call(slot, "goToPage", [0, this.generation]);
            await this.show(slot, state);
        });
    }
    /** Goes to a point through the whole book, from 0 to 1. */
    goToProgression(total) {
        return this.enqueue(async () => {
            const { index, progression } = this.resourceAt(total);
            const slot = await this.load(index);
            await this.show(slot, await this.call(slot, "goToProgression", [progression, this.generation]));
        });
    }
    setPreferences(preferences) {
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
                const state = await this.call(slot, "setPreferences", [this.preferences, this.generation]).catch(() => undefined);
                if (state) {
                    slot.state = state;
                }
                if (slot === current) {
                    await this.report(slot);
                }
            }
        });
    }
    destroy() {
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
    enqueue(work) {
        const run = this.queue.then(() => (this.destroyed ? undefined : work()));
        // A failed step reports and lets the next one run.
        this.queue = run.catch((error) => {
            if (!this.destroyed) {
                this.events.error?.(error);
            }
        });
        return run;
    }
    async open(locator) {
        const [path, fragment] = splitFragment(locator?.href ?? "");
        let index = this.book.indexOf(path);
        let progression = locator?.locations?.progression;
        if (index < 0) {
            // A locator from elsewhere may name the place only by how far through the book it is.
            const total = locator?.locations?.totalProgression;
            ({ index, progression } = total === undefined ? { index: 0, progression: 0 } : this.resourceAt(total));
        }
        const slot = await this.load(index);
        let state = null;
        const text = locator?.text;
        if (text?.highlight) {
            state = await this.call(slot, "goToText", [text.highlight, text.before ?? "", this.generation, progression ?? 0]);
        }
        const fragments = [...(locator?.locations?.fragments ?? []), ...(fragment ? [fragment] : [])];
        if (!state && fragments[0] && progression === undefined) {
            state = await this.call(slot, "goToFragment", [fragments[0], this.generation]);
        }
        state ??= await this.call(slot, "goToProgression", [progression ?? 0, this.generation]);
        await this.show(slot, state);
    }
    async turn(step) {
        const slot = this.current;
        const state = slot?.state;
        if (!slot || !state) {
            return;
        }
        const page = state.page + step;
        if (page >= 0 && page < state.pageCount) {
            await this.show(slot, await this.call(slot, "goToPage", [page, this.generation]));
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
        await this.show(next, await this.call(next, method, args));
    }
    /** The resource and progression within it at a point through the whole book. */
    resourceAt(total) {
        const position = Math.min(Math.max(total, 0), 1) * this.positionCount;
        let index = 0;
        while (index + 1 < this.starts.length && (this.starts[index + 1] ?? Infinity) <= position) {
            index += 1;
        }
        const count = this.book.readingOrder[index]?.positions ?? 1;
        return { index, progression: Math.min(Math.max((position - (this.starts[index] ?? 0)) / count, 0), 1) };
    }
    async show(slot, state) {
        slot.state = state;
        if (this.current !== slot) {
            this.current?.frame.removeAttribute("data-current");
            slot.frame.setAttribute("data-current", "");
            this.current = slot;
        }
        await this.report(slot);
        this.preload(slot.resource);
    }
    preload(origin) {
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
    load(index) {
        const existing = this.slots.find((slot) => slot.resource === index);
        if (existing) {
            return existing.ready.then(() => {
                if (existing.resource !== index || !existing.state) {
                    throw new Error("This part of the book couldn't be opened.");
                }
                return existing;
            });
        }
        let slot;
        if (this.slots.length < maximumSlots) {
            slot = new Slot(this.element, this.options.frameUrl, index);
            this.slots.push(slot);
        }
        else {
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
            target.state = await this.call(target, "paginate", [{
                    layout: item.fixed ? "fixed" : "reflowable",
                    columns: 0,
                    margin: 24,
                    verticalMargin: 32,
                    generation: this.generation,
                }]);
            return target;
        })();
        // Later loads of the same resource wait on this one.
        target.ready = work.then(() => { });
        return work;
    }
    call(slot, method, args) {
        return this.request(slot, { chek: "call", method, args });
    }
    request(slot, message) {
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
    receive = (event) => {
        const slot = this.slots.find((candidate) => candidate.frame.contentWindow === event.source);
        const data = event.data;
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
                }
                else {
                    reply?.resolve(data.result);
                }
                break;
            }
            case "link":
                if (slot === this.current) {
                    if (data.external) {
                        this.events.externalLink?.(data.href);
                    }
                    else {
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
            case "event":
                this.input(slot, data.message);
                break;
        }
    };
    // MARK: Input
    input(slot, message) {
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
        if (slot !== this.current) {
            return;
        }
        const rtl = this.book.metadata.readingProgression === "rtl";
        // Toward the left is forward in a right-to-left book.
        const leftward = rtl ? 1 : -1;
        let step = 0;
        switch (message.type) {
            case "tap":
                if (message.zone === "center") {
                    this.events.tap?.();
                    return;
                }
                step = message.zone === "left" ? leftward : -leftward;
                break;
            case "swipe":
                // Swiping toward the left reveals the page to the right.
                step = message.direction === "left" ? -leftward : leftward;
                break;
            case "wheel":
                step = message.direction === "next" ? 1 : -1;
                break;
            case "key":
                step = this.keyStep(message.key ?? "");
                break;
        }
        if (step !== 0) {
            void this.enqueue(() => this.turn(step));
        }
    }
    keyStep(key) {
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
    keydown = (event) => {
        const target = event.target instanceof Element ? event.target : null;
        if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey
            || target?.closest("input, textarea, select, [contenteditable], [role=dialog], [role=slider], [role=menu], [role=listbox]")
            // Space presses a focused button.
            || (event.key === " " && target?.closest("button, a"))) {
            return;
        }
        const keys = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down", PageDown: "next", PageUp: "previous", " ": event.shiftKey ? "previous" : "next" };
        const step = this.keyStep(keys[event.key] ?? "");
        if (step !== 0) {
            event.preventDefault();
            void this.enqueue(() => this.turn(step));
        }
    };
    // MARK: Locations
    async report(slot) {
        const state = slot.state;
        const item = this.book.readingOrder[slot.resource];
        if (!state || !item) {
            return;
        }
        const text = await this.call(slot, "locate", []).catch(() => null);
        const progression = state.pageCount > 0 ? state.page / state.pageCount : 0;
        const start = this.starts[slot.resource] ?? 0;
        const count = item.positions;
        const offset = Math.min(Math.floor(progression * count), count - 1);
        const atEnd = slot.resource === this.book.readingOrder.length - 1 && state.page >= state.pageCount - 1;
        const chapter = this.chapterOf(item.href);
        const locator = {
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
    chapterOf(href) {
        let found;
        const visit = (items) => {
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
    flatToc() {
        const flat = [];
        const visit = (items) => {
            for (const item of items) {
                flat.push(item);
                visit(item.children);
            }
        };
        visit(this.book.toc);
        return flat;
    }
}
