/** A page's size in pixels. */
export interface PageSize {
    width: number;
    height: number;
}
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
export declare function looksLikeStrip(sizes: PageSize[]): boolean;
/** What sits past either end of the pages: before the first, or after the last. */
export type Edge = "before" | "after";
/** Where a paged comic is: on the screen of pages that starts at `start`, or on an edge. */
export interface PagedPlace {
    start: number;
    edge: Edge | null;
}
/** What a turn does. */
export type Turn = 
/** Shows the screen of pages that starts at `start`. */
{
    kind: "pages";
    start: number;
}
/** Shows what's before the first page or after the last. */
 | {
    kind: "edge";
    edge: Edge;
}
/** Leaves the pages altogether, for what comes after them or before. */
 | {
    kind: "leave";
    toward: Edge;
}
/** Nothing further that way. */
 | {
    kind: "stay";
};
/**
 * Where a turn forward (`direction` 1) or back (-1) leads from `place`.
 * `next` and `previous` are the starts of the screens either side, if any,
 * and `edges` says which ends have something to show.
 *
 * An edge is a place of its own, one turn past the last page and one turn
 * short of leaving, so nothing opens by surprise and a turn back from it
 * returns to the page it came from.
 */
export declare function turn(place: PagedPlace, direction: 1 | -1, around: {
    next: number | undefined;
    previous: number | undefined;
    first: number;
    last: number;
}, edges: {
    before: boolean;
    after: boolean;
}): Turn;
