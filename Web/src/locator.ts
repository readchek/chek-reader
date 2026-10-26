/**
 * A position in a publication, as a [Readium Locator](https://readium.org/architecture/models/locators/).
 * It's the same JSON the Swift package's `Locator` reads and writes, so a
 * position saved on the web opens in the same place on iPhone, and back.
 */
export interface Locator {
    href: string;
    type: string;
    title?: string;
    locations?: {
        fragments?: string[];
        progression?: number;
        totalProgression?: number;
        /** Counts from 1. */
        position?: number;
    };
    text?: { before?: string; highlight?: string; after?: string };
}

/**
 * The href of a comic's page when its pages come one by one from a page
 * source, as `PageSourceContainer` names them in the Swift package:
 * `pages/1` for the first.
 */
export function pageHref(index: number): string {
    return `pages/${index + 1}`;
}

/** The locator at the start of a comic's page, as the Swift package's image navigator reports it. */
export function comicLocator(index: number, count: number, type = "image/jpeg"): Locator {
    return {
        href: pageHref(index),
        type,
        locations: {
            progression: 0,
            position: index + 1,
            totalProgression: count > 0 ? index / count : 0,
        },
    };
}

/**
 * The zero-based page a comic locator points at, or undefined when it
 * names no page of a comic with `count` pages. It reads the href first,
 * then the position, then the total progression, so positions saved by
 * older readers still open near where they were.
 */
export function comicPageIndex(locator: Locator | null | undefined, count: number): number | undefined {
    if (!locator || count <= 0) return undefined;
    const clamp = (index: number) => Math.min(Math.max(index, 0), count - 1);
    const match = /^pages\/(\d+)$/.exec(locator.href);
    if (match) {
        const number = Number(match[1]);
        return number >= 1 && number <= count ? number - 1 : undefined;
    }
    const position = locator.locations?.position;
    if (position !== undefined && Number.isInteger(position) && position >= 1) return clamp(position - 1);
    const total = locator.locations?.totalProgression;
    if (total !== undefined && total >= 0 && total <= 1) return clamp(Math.floor(total * count));
    return undefined;
}
