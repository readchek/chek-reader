// Gets a resource ready for the reader's frame. The frame runs in its own
// origin and can't read the archive, so everything a resource needs is
// sent with it: its markup, with every reference to another resource
// rewritten to `chek:` and its path, and those resources' bytes. The frame
// swaps each `chek:` reference for a URL of its own.
//
// Publication scripts never run. They're removed here, and the frame's
// content security policy blocks any that remain. References outside the
// publication are dropped, so publication content never makes a network
// request.
import { resolveHref, splitFragment } from "./href.js";
export const scheme = "chek:";
/** A `chek:` reference to a path, escaped so it ends cleanly in markup and CSS. */
export function chekReference(path) {
    return scheme + encodeURIComponent(path).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}
// Attributes that load another resource, by the elements they're on.
const loading = {
    img: ["src"],
    image: ["href", "xlink:href"],
    use: ["href", "xlink:href"],
    audio: ["src"],
    video: ["src", "poster"],
    source: ["src"],
    track: ["src"],
    input: ["src"],
};
export async function prepare(epub, path) {
    const text = await (await epub.resource(path)).text();
    const parser = new DOMParser();
    let xml = !/\.html?$/i.test(path) && epub.typeOf(path) !== "text/html";
    let document = parser.parseFromString(text, xml ? "application/xhtml+xml" : "text/html");
    if (xml && document.getElementsByTagName("parsererror").length > 0) {
        // Many books' XHTML isn't well-formed; browsers read it as HTML.
        xml = false;
        document = parser.parseFromString(text, "text/html");
    }
    const resources = {};
    const pending = [];
    const include = (target) => {
        if (target in resources || !epub.has(target)) {
            return;
        }
        // Claimed now so a resource used twice is read once.
        resources[target] = new Blob();
        pending.push((epub.typeOf(target) === "text/css" ? styleSheet(epub, target, include) : epub.resource(target))
            .then((blob) => {
            resources[target] = blob;
        })
            .catch(() => {
            delete resources[target];
        }));
    };
    /** The `chek:` reference for an href, or null when it's outside the publication. */
    const reference = (href) => {
        const resolved = resolveHref(href, path);
        if (!resolved) {
            return null;
        }
        const [target] = splitFragment(resolved);
        if (!epub.has(target)) {
            return null;
        }
        include(target);
        return chekReference(target);
    };
    for (const element of Array.from(document.querySelectorAll("script, base, iframe, object, embed, frame, frameset"))) {
        element.remove();
    }
    for (const meta of Array.from(document.querySelectorAll("meta[http-equiv]"))) {
        meta.remove();
    }
    for (const element of Array.from(document.getElementsByTagName("*"))) {
        for (const attribute of Array.from(element.attributes)) {
            const name = attribute.name.toLowerCase();
            // Event handlers are scripts too.
            if (name.startsWith("on") || name === "srcset" || name === "formaction") {
                element.removeAttribute(attribute.name);
            }
        }
        const local = element.localName.toLowerCase();
        for (const name of loading[local] ?? []) {
            const value = element.getAttribute(name);
            if (value === null) {
                continue;
            }
            const rewritten = reference(value);
            if (rewritten) {
                element.setAttribute(name, rewritten);
            }
            else {
                element.removeAttribute(name);
            }
        }
        if (local === "link") {
            const rel = (element.getAttribute("rel") ?? "").toLowerCase().split(/\s+/);
            const href = element.getAttribute("href");
            const rewritten = rel.includes("stylesheet") && href ? reference(href) : null;
            if (rewritten) {
                element.setAttribute("href", rewritten);
            }
            else {
                element.remove();
            }
            continue;
        }
        if (local === "a" || local === "area") {
            // Links are followed by the reader, not the frame: it keeps the
            // place they point to, and opens outside links elsewhere.
            const href = element.getAttribute("href") ?? element.getAttribute("xlink:href");
            if (href !== null) {
                const resolved = resolveHref(href, path);
                element.setAttribute("data-chek-href", resolved ?? href);
                if (!resolved) {
                    element.setAttribute("data-chek-external", "");
                }
            }
        }
        const style = element.getAttribute("style");
        if (style && /url\(|@import/i.test(style)) {
            element.setAttribute("style", rewriteCss(style, reference));
        }
        if (local === "style" && element.textContent) {
            element.textContent = rewriteCss(element.textContent, reference);
        }
    }
    // Style sheets can pull in more, so wait until nothing new is asked for.
    while (pending.length > 0) {
        await Promise.all(pending.splice(0));
    }
    const markup = xml
        ? new XMLSerializer().serializeToString(document)
        : `<!doctype html>${document.documentElement.outerHTML}`;
    return { markup, xml, resources };
}
/** A style sheet with its references rewritten, reading what it refers to through `include`. */
async function styleSheet(epub, path, include) {
    const text = await (await epub.resource(path)).text();
    const rewritten = rewriteCss(text, (href) => {
        const resolved = resolveHref(href, path);
        if (!resolved) {
            return null;
        }
        const [target] = splitFragment(resolved);
        if (!epub.has(target)) {
            return null;
        }
        include(target);
        return chekReference(target);
    });
    return new Blob([rewritten], { type: "text/css" });
}
/**
 * Rewrites `url()` and `@import` references in CSS with `reference`.
 * References it refuses, such as ones outside the publication, become a
 * URL that loads nothing.
 */
export function rewriteCss(css, reference) {
    const swap = (href) => reference(href.trim()) ?? "about:invalid";
    return css
        .replace(/url\(\s*(['"]?)([^'")]*)\1\s*\)/gi, (_match, quote, href) => href.startsWith("data:") ? `url(${quote}${href}${quote})` : `url("${swap(href)}")`)
        .replace(/@import\s+(['"])([^'"]+)\1/gi, (_match, _quote, href) => `@import "${swap(href)}"`);
}
