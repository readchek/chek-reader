"use strict";
// The reader's own script. It runs in an isolated content world in every
// reflowable resource, so the publication's scripts can't see or call it,
// and it keeps running when publication scripts are turned off.
//
// It lays the resource out in CSS columns, one screen per page, moves
// between pages when the native side asks, and reports input (taps,
// swipes, keys and the scroll wheel) as messages. The native side owns all
// navigation decisions; this script only does what it's told and answers
// with the resulting page state.
const ChekReader = (() => {
    const options = {
        layout: "reflowable",
        columns: 1,
        margin: 0,
        verticalMargin: 0,
        generation: 0,
    };
    /** The reader's margin preference, multiplying `options.margin`. */
    let marginScale = 1;
    let page = 0;
    let pageCount = 1;
    let pageWidth = window.innerWidth;
    let paginated = false;
    function post(message) {
        const handler = window
            .webkit?.messageHandlers?.chekReader;
        handler?.postMessage(message);
    }
    function root() {
        return document.documentElement;
    }
    function state() {
        return {
            page,
            pageCount,
            progression: pageCount > 0 ? page / pageCount : 0,
            generation: options.generation,
        };
    }
    function setImportant(element, property, value) {
        element.style.setProperty(property, value, "important");
    }
    /** Media can't be split across columns, so it's kept within one page. */
    function installMediaStyle(columnHeight) {
        const id = "chek-reader-media";
        let style = document.getElementById(id);
        if (!style) {
            style = document.createElement("style");
            style.id = id;
            (document.head ?? root()).appendChild(style);
        }
        style.textContent = `
            img, svg, video, canvas, iframe, object, embed {
                max-width: 100% !important;
                max-height: ${columnHeight}px !important;
                object-fit: contain;
                break-inside: avoid;
            }
        `;
    }
    function applyReflowable() {
        const width = window.innerWidth;
        const height = window.innerHeight;
        const columns = options.columns > 0
            ? Math.round(options.columns)
            : (width > height && width >= 900 ? 2 : 1);
        const margin = Math.max(0, Math.min(options.margin * marginScale, width / 4));
        const verticalMargin = Math.max(0, Math.min(options.verticalMargin, height / 4));
        const html = root();
        // The body holds the columns and the root scrolls across the ones
        // that overflow.
        const container = document.body ?? html;
        setImportant(html, "margin", "0");
        setImportant(html, "padding", "0");
        setImportant(html, "height", `${height}px`);
        setImportant(html, "max-width", "none");
        setImportant(html, "overflow", "visible");
        // Each page is one viewport wide: `columns` columns separated and
        // edged by `margin`, so column k of page p starts at p * width + margin.
        setImportant(container, "box-sizing", "border-box");
        setImportant(container, "width", `${width}px`);
        setImportant(container, "max-width", "none");
        setImportant(container, "height", `${height}px`);
        setImportant(container, "margin", "0");
        setImportant(container, "padding", `${verticalMargin}px ${margin}px`);
        setImportant(container, "column-count", String(columns));
        // WebKit treats a single column with an automatic width as no
        // columns at all and lets the text run down the page, so the width
        // is given too.
        setImportant(container, "column-width", `${Math.max(1, (width - 2 * margin * columns) / columns)}px`);
        setImportant(container, "column-gap", `${2 * margin}px`);
        setImportant(container, "column-fill", "auto");
        setImportant(container, "overflow", "visible");
        installMediaStyle(height - 2 * verticalMargin);
        pageWidth = width;
    }
    /** Scales a fixed-layout page to fit, centered, using its viewport size. */
    function applyFixed() {
        const width = window.innerWidth;
        const height = window.innerHeight;
        const size = declaredViewport() ?? { width: root().scrollWidth || width, height: root().scrollHeight || height };
        const scale = Math.min(width / size.width, height / size.height);
        const html = root();
        setImportant(html, "width", `${size.width}px`);
        setImportant(html, "height", `${size.height}px`);
        setImportant(html, "overflow", "hidden");
        setImportant(html, "transform-origin", "0 0");
        const x = (width - size.width * scale) / 2;
        const y = (height - size.height * scale) / 2;
        setImportant(html, "transform", `translate(${x}px, ${y}px) scale(${scale})`);
        if (document.body) {
            setImportant(document.body, "margin", "0");
        }
        pageWidth = width;
    }
    function declaredViewport() {
        const content = document.querySelector('meta[name="viewport"]')?.content ?? "";
        const values = new Map();
        for (const part of content.split(/[,;]/)) {
            const [key, value] = part.split("=").map((piece) => piece.trim().toLowerCase());
            const number = Number.parseFloat(value ?? "");
            if (key && Number.isFinite(number) && number > 0) {
                values.set(key, number);
            }
        }
        const width = values.get("width");
        const height = values.get("height");
        return width && height ? { width, height } : null;
    }
    function measure() {
        if (options.layout === "fixed") {
            pageCount = 1;
            page = 0;
            return;
        }
        // The last page may hold fewer columns, so round up. One pixel of
        // slack absorbs subpixel widths that would otherwise add a blank page.
        pageCount = Math.max(1, Math.ceil((Math.max(scrollExtent(), contentExtent()) - 1) / pageWidth));
        page = Math.min(page, pageCount - 1);
    }
    function scrollExtent() {
        return (document.scrollingElement ?? root()).scrollWidth;
    }
    /**
     * How far the content reaches from the start of the first page, in the
     * direction pages advance, measured from the content itself so it
     * doesn't depend on how the engine reports scroll sizes.
     */
    function contentExtent() {
        const body = document.body;
        if (!body) {
            return 0;
        }
        const range = document.createRange();
        range.selectNodeContents(body);
        const rect = range.getBoundingClientRect();
        const scroller = document.scrollingElement ?? root();
        return isRightToLeft()
            ? window.innerWidth - rect.left - scroller.scrollLeft
            : rect.right + scroller.scrollLeft;
    }
    /** Diagnostics for the tests: the sizes the page count came from. */
    function metrics() {
        const scroller = document.scrollingElement ?? root();
        const body = document.body;
        const last = body?.lastElementChild?.getBoundingClientRect();
        return {
            scrollExtent: scrollExtent(),
            contentExtent: contentExtent(),
            scrollLeft: scroller.scrollLeft,
            pageWidth,
            scrollHeight: scroller.scrollHeight,
            compatMode: document.compatMode,
            columnCount: body ? getComputedStyle(body).columnCount : null,
            bodyHeight: body?.getBoundingClientRect().height,
            last: last ? [last.left, last.top, last.right, last.bottom] : null,
        };
    }
    /** Right-to-left text lays its columns out from the right, with negative scroll offsets. */
    function isRightToLeft() {
        return getComputedStyle(root()).direction === "rtl";
    }
    function scrollToPage() {
        const scroller = document.scrollingElement ?? root();
        scroller.scrollLeft = (isRightToLeft() ? -1 : 1) * page * pageWidth;
        scroller.scrollTop = 0;
    }
    async function waitForContent() {
        await document.fonts?.ready;
        const pending = Array.from(document.images)
            .filter((image) => !image.complete)
            .map((image) => image.decode().catch(() => undefined));
        // A broken or slow image mustn't hold the page back for long.
        await Promise.race([Promise.all(pending), new Promise((resolve) => setTimeout(resolve, 500))]);
    }
    /**
     * Lays reflowable text out at the device's width. Most EPUBs have no
     * viewport tag, and without one WebKit on iOS lays a page out 980
     * pixels wide and scales it down, so text comes out tiny with hairline
     * margins. Returns whether the viewport changed.
     */
    function fitViewportToDevice() {
        const content = "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no";
        let meta = document.querySelector('meta[name="viewport"]');
        if (meta?.content === content) {
            return false;
        }
        if (!meta) {
            meta = document.createElement("meta");
            meta.name = "viewport";
            (document.head ?? root()).prepend(meta);
        }
        meta.content = content;
        return true;
    }
    /** Lays the resource out and moves to its first page. */
    async function paginate(next) {
        Object.assign(options, next);
        if (options.layout !== "fixed" && fitViewportToDevice()) {
            // The new viewport takes effect at the next layout.
            await new Promise((resolve) => window.requestAnimationFrame(() => resolve()));
        }
        await waitForContent();
        page = 0;
        relayoutNow();
        paginated = true;
        return state();
    }
    /**
     * Lays the resource out again, for example after a resize, keeping the
     * text at the start of the page on screen.
     */
    function relayout(generation) {
        options.generation = generation;
        const anchor = options.layout === "reflowable" ? pinned ?? locate() : null;
        const progression = state().progression;
        relayoutNow();
        return restore(anchor, progression, generation);
    }
    function relayoutNow() {
        if (options.layout === "fixed") {
            applyFixed();
        }
        else {
            applyReflowable();
        }
        measure();
        scrollToPage();
    }
    /**
     * The text a relayout keeps on screen. It's kept across relayouts, so
     * several in a row don't drift, and cleared when the reader moves.
     */
    let pinned = null;
    function goToPage(target, generation) {
        pinned = null;
        return showPage(target, generation);
    }
    function showPage(target, generation) {
        options.generation = generation;
        page = Math.max(0, Math.min(pageCount - 1, Math.floor(target)));
        scrollToPage();
        return state();
    }
    function goToLastPage(generation) {
        return goToPage(pageCount - 1, generation);
    }
    function goToProgression(progression, generation) {
        const clamped = Math.max(0, Math.min(1, progression));
        return goToPage(Math.floor(clamped * pageCount + 1e-6), generation);
    }
    /** The page a box on screen is on, counted in the direction pages advance. */
    function pageOf(rect) {
        const scroller = document.scrollingElement ?? root();
        const offset = isRightToLeft()
            ? window.innerWidth - rect.right - scroller.scrollLeft
            : rect.left + scroller.scrollLeft;
        return Math.max(0, Math.min(pageCount - 1, Math.floor(Math.max(0, offset) / pageWidth)));
    }
    /** Moves to the page holding the element with `id`. Returns null when there's none. */
    function goToFragment(id, generation) {
        const element = document.getElementById(id) ?? document.getElementsByName(id)[0];
        if (!element) {
            return null;
        }
        return goToPage(pageOf(element.getBoundingClientRect()), generation);
    }
    // MARK: Text anchors
    /** How much text on each side of a position identifies it. */
    const anchorLength = 32;
    /** The visible text of the document as one string, with each text node's start. */
    function textIndex() {
        const nodes = [];
        let text = "";
        const walker = document.createTreeWalker(document.body ?? root(), NodeFilter.SHOW_TEXT, {
            acceptNode: (node) => {
                const parent = node.parentElement;
                return parent && !parent.closest("script, style, head") ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            },
        });
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            nodes.push({ node: node, start: text.length });
            text += node.nodeValue ?? "";
        }
        return { text, nodes };
    }
    /** Collapses runs of whitespace, so anchors survive reformatting. */
    function normalized(text) {
        return text.replace(/\s+/g, " ");
    }
    /**
     * The text at the start of the current page, with some text before it,
     * so the same spot can be found after the layout changes.
     */
    function locate() {
        const { text, nodes } = textIndex();
        if (nodes.length === 0) {
            return null;
        }
        // The first text node, and the first character in it, that's on this page.
        for (const { node, start } of nodes) {
            const length = node.nodeValue?.length ?? 0;
            if (length === 0 || !node.nodeValue?.trim()) {
                continue;
            }
            const range = document.createRange();
            range.selectNodeContents(node);
            const rects = Array.from(range.getClientRects());
            if (!rects.some((rect) => rect.width > 0 && pageOf(rect) >= page)) {
                continue;
            }
            // Binary search for the first character on this page or later.
            let low = 0;
            let high = length - 1;
            while (low < high) {
                const middle = (low + high) >> 1;
                range.setStart(node, middle);
                range.setEnd(node, middle + 1);
                const rect = range.getClientRects()[0];
                if (rect && pageOf(rect) >= page) {
                    high = middle;
                }
                else {
                    low = middle + 1;
                }
            }
            let offset = start + low;
            // Start at a word, not in the middle of one.
            while (offset < text.length && /\s/.test(text[offset] ?? "")) {
                offset += 1;
            }
            return {
                before: normalized(text.slice(Math.max(0, offset - anchorLength), offset)),
                highlight: normalized(text.slice(offset, offset + anchorLength)),
                after: normalized(text.slice(offset + anchorLength, offset + 2 * anchorLength)),
            };
        }
        return null;
    }
    /** Every index of `target` in `text`, up to a bound. */
    function occurrences(text, target) {
        const found = [];
        for (let index = text.indexOf(target); index >= 0 && found.length < 1000; index = text.indexOf(target, index + 1)) {
            found.push(index);
        }
        return found;
    }
    /**
     * Moves to the page holding `highlight`, preferring occurrences that
     * follow `before`, and of those the one nearest `near`, a progression
     * through the resource. Returns null when the text isn't in the resource.
     */
    function goToText(highlight, before, generation, near) {
        const { text, nodes } = textIndex();
        // Search normalized text, keeping a map back to raw offsets.
        let flat = "";
        const raw = [];
        for (let index = 0; index < text.length; index += 1) {
            const character = text[index] ?? "";
            if (/\s/.test(character)) {
                if (flat.endsWith(" ")) {
                    continue;
                }
                flat += " ";
            }
            else {
                flat += character;
            }
            raw.push(index);
        }
        const target = normalized(highlight);
        if (!target.trim()) {
            return null;
        }
        const context = normalized(before);
        const withContext = context ? occurrences(flat, context + target).map((index) => index + context.length) : [];
        const candidates = withContext.length > 0 ? withContext : occurrences(flat, target);
        if (candidates.length === 0) {
            return null;
        }
        // Repeated text, such as a refrain, matches in several places.
        const goal = near !== undefined && Number.isFinite(near) && near >= 0 ? Math.min(near, 1) * flat.length : 0;
        const found = candidates.reduce((best, index) => Math.abs(index - goal) < Math.abs(best - goal) ? index : best);
        const offset = raw[found] ?? 0;
        const entry = [...nodes].reverse().find(({ start }) => start <= offset);
        if (!entry) {
            return null;
        }
        const range = document.createRange();
        const within = Math.min(offset - entry.start, Math.max(0, (entry.node.nodeValue?.length ?? 1) - 1));
        range.setStart(entry.node, within);
        range.setEnd(entry.node, Math.min(within + 1, entry.node.nodeValue?.length ?? 0));
        const rect = range.getClientRects()[0] ?? range.getBoundingClientRect();
        const state = showPage(pageOf(rect), generation);
        pinned = { highlight, before };
        return state;
    }
    const fonts = {
        serif: `ui-serif, "New York", Georgia, serif`,
        sans: `system-ui, -apple-system, "Helvetica Neue", sans-serif`,
    };
    const themes = {
        light: { text: "#1d1d1f", background: "#ffffff", link: "#0b57d0" },
        sepia: { text: "#4b3a26", background: "#f5ecd9", link: "#7a4b12" },
        dark: { text: "#e8e6e3", background: "#121212", link: "#8ab4f8" },
    };
    /** Applies `preferences`, lays the resource out again and keeps the reading position. */
    function setPreferences(preferences, generation) {
        const anchor = paginated ? pinned ?? locate() : null;
        const progression = state().progression;
        const id = "chek-reader-preferences";
        let style = document.getElementById(id);
        if (!style) {
            style = document.createElement("style");
            style.id = id;
            (document.head ?? root()).appendChild(style);
        }
        const scale = Math.max(0.5, Math.min(3, Number.isFinite(preferences.fontScale) ? preferences.fontScale : 1));
        const theme = preferences.theme === "default" ? null : themes[preferences.theme];
        const font = preferences.font && preferences.font !== "default" ? fonts[preferences.font] : null;
        const lineHeight = Number.isFinite(preferences.lineHeight) && (preferences.lineHeight ?? 0) > 0
            ? Math.max(1, Math.min(2.5, preferences.lineHeight ?? 0))
            : null;
        marginScale = Number.isFinite(preferences.marginScale) ? Math.max(0, Math.min(3, preferences.marginScale ?? 1)) : 1;
        style.textContent = `
            html { font-size: ${scale * 100}% !important; -webkit-text-size-adjust: none; }
            ${font ? `body, body :not(code):not(pre):not(kbd):not(samp) { font-family: ${font} !important; }` : ""}
            ${lineHeight ? `body, body * { line-height: ${lineHeight} !important; }` : ""}
            ${theme ? `
            html, body { background: ${theme.background} !important; color: ${theme.text} !important; }
            body * { color: inherit !important; background-color: transparent !important; border-color: currentColor !important; }
            a, a * { color: ${theme.link} !important; }
            ` : ""}
        `;
        if (!paginated || options.layout === "fixed") {
            return state();
        }
        options.generation = generation;
        relayoutNow();
        return restore(anchor, progression, generation);
    }
    /** Shows `anchor` after a relayout, or `progression` when the text can't be found. */
    function restore(anchor, progression, generation) {
        const restored = anchor ? goToText(anchor.highlight, anchor.before, generation, progression) : null;
        if (restored) {
            return restored;
        }
        const state = goToProgression(progression, generation);
        pinned = anchor;
        return state;
    }
    // Content that grows after layout, such as late images, can add pages.
    if (typeof ResizeObserver !== "undefined") {
        new ResizeObserver(() => {
            if (!paginated || options.layout === "fixed") {
                return;
            }
            const before = pageCount;
            measure();
            if (pageCount !== before) {
                scrollToPage();
                post({ type: "layout", ...state() });
            }
        }).observe(document.body ?? root());
    }
    // The web view can change size, or get its first real size after a
    // page loaded off screen, so lay out again and tell the native side.
    let resizeFrame = 0;
    window.addEventListener("resize", () => {
        if (!paginated) {
            return;
        }
        window.cancelAnimationFrame(resizeFrame);
        resizeFrame = window.requestAnimationFrame(() => {
            post({ type: "layout", ...relayout(options.generation) });
        });
    });
    // MARK: Input
    const interactive = "a, button, input, select, textarea, label, summary, audio, video, [contenteditable], [role=button]";
    document.addEventListener("click", (event) => {
        if (event.defaultPrevented || !(event.target instanceof Element) || event.target.closest(interactive)) {
            return;
        }
        if (!(window.getSelection()?.isCollapsed ?? true)) {
            return;
        }
        const x = event.clientX / window.innerWidth;
        post({ type: "tap", zone: x < 0.3 ? "left" : x > 0.7 ? "right" : "center" });
    });
    let touchStart = null;
    document.addEventListener("touchstart", (event) => {
        const touch = event.touches[0];
        touchStart = event.touches.length === 1 && touch ? { x: touch.clientX, y: touch.clientY } : null;
    }, { passive: true });
    // Stop the web view panning between columns itself; page turns are native.
    document.addEventListener("touchmove", (event) => {
        const touch = event.touches[0];
        if (paginated && options.layout === "reflowable" && touchStart && touch
            && Math.abs(touch.clientX - touchStart.x) > Math.abs(touch.clientY - touchStart.y)) {
            event.preventDefault();
        }
    }, { passive: false });
    document.addEventListener("touchend", (event) => {
        const touch = event.changedTouches[0];
        if (!touchStart || !touch) {
            return;
        }
        const dx = touch.clientX - touchStart.x;
        const dy = touch.clientY - touchStart.y;
        touchStart = null;
        if (Math.abs(dx) > 40 && Math.abs(dx) > 1.5 * Math.abs(dy)) {
            post({ type: "swipe", direction: dx < 0 ? "left" : "right" });
        }
    });
    const keys = {
        ArrowLeft: "left",
        ArrowRight: "right",
        ArrowUp: "up",
        ArrowDown: "down",
        PageDown: "next",
        PageUp: "previous",
        Home: "home",
        End: "end",
    };
    document.addEventListener("keydown", (event) => {
        if (event.metaKey || event.ctrlKey || event.altKey
            || (event.target instanceof Element && event.target.closest("input, textarea, select, [contenteditable]"))) {
            return;
        }
        const key = event.key === " " ? (event.shiftKey ? "previous" : "next") : keys[event.key];
        if (key) {
            event.preventDefault();
            post({ type: "key", key });
        }
    });
    // A trackpad or wheel turns one page per gesture, not one per event.
    let wheelTotal = 0;
    let wheelLocked = false;
    let wheelTimer;
    document.addEventListener("wheel", (event) => {
        if (!paginated || options.layout !== "reflowable") {
            return;
        }
        event.preventDefault();
        window.clearTimeout(wheelTimer);
        wheelTimer = window.setTimeout(() => {
            wheelTotal = 0;
            wheelLocked = false;
        }, 200);
        if (wheelLocked) {
            return;
        }
        wheelTotal += Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
        if (Math.abs(wheelTotal) > 60) {
            wheelLocked = true;
            post({ type: "wheel", direction: wheelTotal > 0 ? "next" : "previous" });
        }
    }, { passive: false });
    return {
        paginate, relayout, goToPage, goToLastPage, goToProgression, goToFragment, goToText, locate, setPreferences, state, metrics,
    };
})();
globalThis.chekReader = ChekReader;
