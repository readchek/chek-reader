// The decisions a comic's view makes that don't need a page to make them:
// whether a run of pages is a vertical strip, and where a turn leads when
// the pages have something before and after them, such as what joins one
// chapter to the next. Kept apart from the view so they can be tested
// without a browser, and so the Swift package's rules can be held to them.
/**
 * Whether pages of these sizes are a strip meant to be scrolled, as a
 * webtoon's are, rather than pages meant to be turned.
 *
 * A strip is either drawn as pages much taller than they are wide, or cut
 * by its site into pieces of one width whose heights are whatever the cut
 * left. Printed pages share a shape instead: a manga page is about 1.45
 * times as tall as wide and a comic about 1.55, and a spread among them is
 * wider than its neighbors, not taller.
 */
export function looksLikeStrip(sizes) {
    const pages = sizes.filter((size) => size.width > 0 && size.height > 0);
    if (pages.length === 0)
        return false;
    const ratios = pages.map((page) => page.height / page.width);
    const tall = ratios.filter((ratio) => ratio > 2).length;
    if (tall * 2 > pages.length)
        return true;
    if (pages.length < 3)
        return false;
    const widths = pages.map((page) => page.width);
    const sameWidth = Math.max(...widths) <= Math.min(...widths) * 1.02;
    if (!sameWidth)
        return false;
    // Cut pieces: taller than any printed page for the most part, or of
    // heights that differ far more than pages of one book do.
    const longish = ratios.filter((ratio) => ratio >= 1.7).length;
    if (longish * 2 > pages.length)
        return true;
    const heights = pages.map((page) => page.height);
    return Math.max(...heights) > Math.min(...heights) * 1.25 && Math.max(...ratios) >= 1.7;
}
/**
 * Where a turn forward (`direction` 1) or back (-1) leads from `place`.
 * `next` and `previous` are the starts of the screens either side, if any,
 * and `edges` says which ends have something to show.
 *
 * An edge is a place of its own, one turn past the last page and one turn
 * short of leaving, so nothing opens by surprise and a turn back from it
 * returns to the page it came from.
 */
export function turn(place, direction, around, edges) {
    if (place.edge === "after") {
        return direction === 1 ? { kind: "leave", toward: "after" } : { kind: "pages", start: around.last };
    }
    if (place.edge === "before") {
        return direction === -1 ? { kind: "leave", toward: "before" } : { kind: "pages", start: around.first };
    }
    if (direction === 1) {
        if (around.next !== undefined)
            return { kind: "pages", start: around.next };
        return edges.after ? { kind: "edge", edge: "after" } : { kind: "stay" };
    }
    if (around.previous !== undefined)
        return { kind: "pages", start: around.previous };
    return edges.before ? { kind: "edge", edge: "before" } : { kind: "stay" };
}
