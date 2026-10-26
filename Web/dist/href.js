// Hrefs inside a publication, resolved to paths from its root, as the
// Swift package's EPUBHref does, so locators name resources the same way
// on every platform.
/**
 * Resolves `href`, written in the document at `base`, to a percent-decoded
 * path with its fragment kept. Returns null for hrefs with a scheme, such
 * as `https:`, and for paths that climb above the publication's root.
 */
export function resolveHref(href, base) {
    const trimmed = href.trim();
    if (hasScheme(trimmed)) {
        return null;
    }
    let path = trimmed;
    let fragment;
    const hash = path.indexOf("#");
    if (hash >= 0) {
        fragment = path.slice(hash + 1);
        path = path.slice(0, hash);
    }
    const query = path.indexOf("?");
    if (query >= 0) {
        path = path.slice(0, query);
    }
    const decoded = decode(path);
    let components;
    if (decoded === "") {
        // A bare fragment points into the base document itself.
        components = base.split("/").filter(Boolean);
    }
    else if (decoded.startsWith("/")) {
        components = [];
    }
    else {
        components = base.split("/").filter(Boolean).slice(0, -1);
    }
    if (decoded !== "") {
        for (const component of decoded.split("/").filter(Boolean)) {
            if (component === ".") {
                continue;
            }
            if (component === "..") {
                if (components.pop() === undefined) {
                    return null;
                }
                continue;
            }
            components.push(component);
        }
    }
    if (components.length === 0) {
        return null;
    }
    const resolved = components.join("/");
    return fragment ? `${resolved}#${decode(fragment)}` : resolved;
}
/** `path` without its fragment, and the fragment, if any. */
export function splitFragment(path) {
    const hash = path.indexOf("#");
    return hash < 0 ? [path, undefined] : [path.slice(0, hash), path.slice(hash + 1) || undefined];
}
function decode(text) {
    try {
        return decodeURIComponent(text);
    }
    catch {
        return text;
    }
}
function hasScheme(href) {
    return /^[a-z][a-z0-9+.-]*:/i.test(href);
}
