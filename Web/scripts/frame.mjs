// Puts the frame's page and the Swift package's reader.js next to the
// compiled frame.js, so Web/dist/frame holds every file an app serves.
import { copyFileSync } from "node:fs"

const root = new URL("../../", import.meta.url)
const out = new URL("Web/dist/frame/", root)
copyFileSync(new URL("Web/frame/frame.html", root), new URL("frame.html", out))
copyFileSync(new URL("Sources/ChekReaderNavigator/Resources/reader.js", root), new URL("reader.js", out))
