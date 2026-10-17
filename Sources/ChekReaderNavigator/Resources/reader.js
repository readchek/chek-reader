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
        const margin = Math.max(0, Math.min(options.margin, width / 4));
        const verticalMargin = Math.max(0, Math.min(options.verticalMargin, height / 4));
        const html = root();
        // WebKit doesn't lay the root element out in columns, so the body
        // holds them and the root scrolls across the columns that overflow.
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
    /** Lays the resource out and moves to its first page. */
    async function paginate(next) {
        Object.assign(options, next);
        await waitForContent();
        page = 0;
        relayoutNow();
        paginated = true;
        return state();
    }
    /** Lays the resource out again, for example after a resize, keeping the progression. */
    function relayout(generation) {
        options.generation = generation;
        const progression = state().progression;
        relayoutNow();
        page = Math.min(pageCount - 1, Math.floor(progression * pageCount + 1e-6));
        scrollToPage();
        return state();
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
    function goToPage(target, generation) {
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
    /** Moves to the page holding the element with `id`. Returns null when there's none. */
    function goToFragment(id, generation) {
        const element = document.getElementById(id) ?? document.getElementsByName(id)[0];
        if (!element) {
            return null;
        }
        // The element's distance from the start of the first page, in the
        // direction pages advance.
        const scroller = document.scrollingElement ?? root();
        const rect = element.getBoundingClientRect();
        const offset = isRightToLeft()
            ? window.innerWidth - rect.right - scroller.scrollLeft
            : rect.left + scroller.scrollLeft;
        return goToPage(Math.floor(Math.max(0, offset) / pageWidth), generation);
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
    return { paginate, relayout, goToPage, goToLastPage, goToProgression, goToFragment, state, metrics };
})();
globalThis.chekReader = ChekReader;
