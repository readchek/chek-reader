/** The first page of the screen that shows `page`. */
export declare function screenStart(page: number, spreads: boolean): number;
/** Every page on the screen that starts at `start`, in reading order. */
export declare function screenPages(start: number, count: number, spreads: boolean): number[];
/** The start of the next screen, or undefined after the last. */
export declare function nextScreen(start: number, count: number, spreads: boolean): number | undefined;
/** The start of the previous screen, or undefined before the first. */
export declare function previousScreen(start: number, spreads: boolean): number | undefined;
