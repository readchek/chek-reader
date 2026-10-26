/**
 * Resolves `href`, written in the document at `base`, to a percent-decoded
 * path with its fragment kept. Returns null for hrefs with a scheme, such
 * as `https:`, and for paths that climb above the publication's root.
 */
export declare function resolveHref(href: string, base: string): string | null;
/** `path` without its fragment, and the fragment, if any. */
export declare function splitFragment(path: string): [string, string | undefined];
