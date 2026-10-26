// The reader's frame: a page the app serves from its own origin and
// sandboxes into an origin of its own, so publication content can't reach
// the app. It takes one resource from the reader, prepared by prepare.ts,
// puts it in place of itself, then loads the Swift package's own reader
// script, reader.js, and runs its commands for the reader.
//
// It's a classic script, not a module: a module from a sandboxed frame
// would be fetched with CORS, which static hosting doesn't answer.

(() => {
    type Load = { chek: "load"; id: number; markup: string; xml: boolean; resources: Record<string, Blob>; fixed: boolean };
    type Call = { chek: "call"; id: number; method: string; args: unknown[] };
    type Request = Load | Call;

    const scheme = "chek:";
    const urls = new Map<string, string>();

    function send(message: Record<string, unknown>): void {
        // The frame's origin is opaque, so it can't name the app's.
        parent.postMessage({ chekFrame: true, ...message }, "*");
    }

    // reader.js posts input and layout changes to WebKit's message
    // handler, as in the Swift package's web views; here they go to the reader.
    (window as unknown as { webkit: unknown }).webkit = {
        messageHandlers: {
            chekReader: {
                postMessage(message: unknown) {
                    send({ type: "event", message });
                },
            },
        },
    };

    /** Swaps every `chek:` reference in `text` for the URL of what it names. */
    function swap(text: string): string {
        return text.replace(/chek:([A-Za-z0-9%._~-]+)/g, (match, path: string) => urls.get(decodeURIComponent(path)) ?? match);
    }

    async function load(request: Load): Promise<void> {
        // Style sheets refer to other resources, so the rest get URLs first.
        const sheets: [string, Blob][] = [];
        for (const [path, blob] of Object.entries(request.resources)) {
            if (blob.type === "text/css") {
                sheets.push([path, blob]);
            } else {
                urls.set(path, URL.createObjectURL(blob));
            }
        }
        // A sheet can import another, so those are swapped in more rounds.
        for (let round = 0; round < 4 && sheets.length > 0; round += 1) {
            for (const [path, blob] of sheets) {
                urls.set(path, URL.createObjectURL(new Blob([swap(await blob.text())], { type: "text/css" })));
            }
        }

        const parsed = new DOMParser().parseFromString(request.markup, request.xml ? "application/xhtml+xml" : "text/html");
        for (const element of Array.from(parsed.getElementsByTagName("*"))) {
            for (const attribute of Array.from(element.attributes)) {
                if (attribute.value.includes(scheme)) {
                    element.setAttribute(attribute.name, swap(attribute.value));
                }
            }
            if (element.localName === "style" && element.textContent?.includes(scheme)) {
                element.textContent = swap(element.textContent);
            }
        }
        const root = document.importNode(parsed.documentElement, true);
        document.replaceChild(root, document.documentElement);
        let head = document.head;
        if (!head) {
            head = document.createElement("head");
            root.insertBefore(head, root.firstChild);
        }
        if (!request.fixed) {
            // Most books have no viewport, and without one a phone lays the
            // page out wide and scales it down. Fixed-layout pages keep
            // theirs, which says how big the page is.
            for (const meta of Array.from(head.querySelectorAll("meta[name=viewport]"))) {
                meta.remove();
            }
            const meta = document.createElement("meta");
            meta.name = "viewport";
            meta.content = "width=device-width, initial-scale=1";
            head.appendChild(meta);
        }

        // Links are the reader's to follow. This runs before reader.js's
        // own click handler, which leaves alone clicks already handled.
        document.addEventListener("click", (event) => {
            const link = event.target instanceof Element ? event.target.closest("[data-chek-href]") : null;
            if (!link) {
                return;
            }
            event.preventDefault();
            send({
                type: "link",
                href: link.getAttribute("data-chek-href"),
                external: link.hasAttribute("data-chek-external"),
            });
        });

        await new Promise<void>((resolve, reject) => {
            const script = document.createElement("script");
            script.src = "reader.js";
            script.onload = () => resolve();
            script.onerror = () => reject(new Error("reader.js couldn't be loaded next to the frame."));
            head.appendChild(script);
        });
    }

    async function call(request: Call): Promise<unknown> {
        const reader = (globalThis as unknown as { chekReader?: Record<string, (...args: unknown[]) => unknown> }).chekReader;
        const method = reader?.[request.method];
        if (typeof method !== "function") {
            throw new Error(`The reader script has no ${request.method}.`);
        }
        return await method(...request.args);
    }

    window.addEventListener("message", (event) => {
        if (event.source !== parent) {
            return;
        }
        const request = event.data as Request;
        if (!request || (request.chek !== "load" && request.chek !== "call")) {
            return;
        }
        const work = request.chek === "load" ? load(request) : call(request);
        work.then(
            (result) => send({ type: "reply", id: request.id, result: result ?? null }),
            (error: unknown) => send({ type: "reply", id: request.id, error: error instanceof Error ? error.message : String(error) }),
        );
    });

    send({ type: "ready" });
})();
