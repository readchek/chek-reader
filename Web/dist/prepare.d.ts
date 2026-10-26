import type { Epub } from "./epub.js";
/** A resource ready for the frame. */
export interface PreparedResource {
    /** The resource's markup. */
    markup: string;
    /** Whether `markup` is XHTML, parsed as XML, rather than HTML. */
    xml: boolean;
    /** The bytes of every resource the markup refers to, by path. Style sheets have their own references rewritten. */
    resources: Record<string, Blob>;
}
export declare const scheme = "chek:";
/** A `chek:` reference to a path, escaped so it ends cleanly in markup and CSS. */
export declare function chekReference(path: string): string;
export declare function prepare(epub: Epub, path: string): Promise<PreparedResource>;
/**
 * Rewrites `url()` and `@import` references in CSS with `reference`.
 * References it refuses, such as ones outside the publication, become a
 * URL that loads nothing.
 */
export declare function rewriteCss(css: string, reference: (href: string) => string | null): string;
