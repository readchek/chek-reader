// Which pages show together when a comic opens as a book. The cover stands
// alone, as on the right of a printed book's first spread, and the rest
// pair up: 2 and 3, 4 and 5. It's the grouping the Swift package's image
// pager uses, so a spread on the web holds the same two pages as on iPad.

/** The first page of the screen that shows `page`. */
export function screenStart(page: number, spreads: boolean): number {
    if (!spreads || page <= 0) return page;
    return page % 2 === 0 ? page - 1 : page;
}

/** Every page on the screen that starts at `start`, in reading order. */
export function screenPages(start: number, count: number, spreads: boolean): number[] {
    if (start < 0 || start >= count) return [];
    if (!spreads || start === 0 || start + 1 >= count) return [start];
    return [start, start + 1];
}

/** The start of the next screen, or undefined after the last. */
export function nextScreen(start: number, count: number, spreads: boolean): number | undefined {
    const next = spreads && start > 0 ? start + 2 : start + 1;
    return next < count ? next : undefined;
}

/** The start of the previous screen, or undefined before the first. */
export function previousScreen(start: number, spreads: boolean): number | undefined {
    if (start <= 0) return undefined;
    return spreads ? screenStart(Math.max(start - 2, 0), true) : start - 1;
}
