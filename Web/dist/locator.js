/**
 * The href of a comic's page when its pages come one by one from a page
 * source, as `PageSourceContainer` names them in the Swift package:
 * `pages/1` for the first.
 */
export function pageHref(index) {
    return `pages/${index + 1}`;
}
/** The locator at the start of a comic's page, as the Swift package's image navigator reports it. */
export function comicLocator(index, count, type = "image/jpeg") {
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
export function comicPageIndex(locator, count) {
    if (!locator || count <= 0)
        return undefined;
    const clamp = (index) => Math.min(Math.max(index, 0), count - 1);
    const match = /^pages\/(\d+)$/.exec(locator.href);
    if (match) {
        const number = Number(match[1]);
        return number >= 1 && number <= count ? number - 1 : undefined;
    }
    const position = locator.locations?.position;
    if (position !== undefined && Number.isInteger(position) && position >= 1)
        return clamp(position - 1);
    const total = locator.locations?.totalProgression;
    if (total !== undefined && total >= 0 && total <= 1)
        return clamp(Math.floor(total * count));
    return undefined;
}
/** The href of a PDF's one resource, as the Swift package's `PDFModule.href`. */
export const pdfHref = "publication.pdf";
/** The locator of a PDF's page, from 0, as the Swift package's PDF navigator reports it. */
export function pdfLocator(index, count, title) {
    const progression = count > 0 ? index / count : 0;
    return {
        href: pdfHref,
        type: "application/pdf",
        ...(title ? { title } : {}),
        locations: {
            fragments: [`page=${index + 1}`],
            progression,
            position: index + 1,
            totalProgression: progression,
        },
    };
}
/** The page from 0 a PDF locator points at: its `page=N` fragment, else its position, else its progression. */
export function pdfPageIndex(locator, count) {
    if (!locator || count <= 0)
        return undefined;
    const clamp = (index) => Math.min(Math.max(index, 0), count - 1);
    const fragments = [...(locator.locations?.fragments ?? []), locator.href.split("#")[1] ?? ""];
    for (const fragment of fragments) {
        for (const parameter of fragment.split("&")) {
            const match = /^page=(\d+)$/.exec(parameter);
            if (match)
                return clamp(Number(match[1]) - 1);
        }
    }
    const position = locator.locations?.position;
    if (position !== undefined && Number.isInteger(position) && position >= 1)
        return clamp(position - 1);
    const progression = locator.locations?.totalProgression ?? locator.locations?.progression;
    if (progression !== undefined && progression >= 0 && progression <= 1)
        return clamp(Math.floor(progression * count));
    return undefined;
}
