import { TuiApp } from "../src/app";
import { BoxElement } from "../src/elements";

const app = new TuiApp();

const root = new BoxElement();
root.setProps({
    style: { flex_grow: 1 },
    bg: { type: "rgb", r: 255, g: 0, b: 0 },
});

root.on("keydown", (event) => {
    const data = event.data as { codepoint: number; mods: number };
    if (data.codepoint === 99 && (data.mods & 4) !== 0) {
        app.destroy();
        process.exit(0);
    }
});

app.setRoot(root);
app.flush();
app.start();
