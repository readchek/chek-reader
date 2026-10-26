// Chek Reader for the web: the same reading engine as the Swift package,
// for any web app. It draws pages into an element you give it, and leaves
// controls, storage and networking to the app.

export { type Locator, comicLocator, comicPageIndex, pageHref } from "./locator.js";
export { nextScreen, previousScreen, screenPages, screenStart } from "./spreads.js";
export {
    type ComicEvents,
    type ComicFlow,
    type ComicLocation,
    type ComicOptions,
    ComicView,
    type PageSource,
    type ReadingDirection,
    type Spreads,
} from "./comic.js";
