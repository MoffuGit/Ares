import { CoreApp } from "@ares/shared/core";
import { log } from "../../../tui/solid/src/utils";

export class TuiApp extends CoreApp {
    constructor(settingsPath: string, projectPath: string, libPath?: string,) {
        super(libPath);

        this.loadSettings(settingsPath, null);
        this.openProject(projectPath);
    }

    start() {
        this.on("filetreeUpdate", () => this.events.emit("filetreeUpdate"));
        this.on("settingsUpdate", () => this.events.emit("settingsUpdate"));
        this.on("themeUpdate", () => this.events.emit("themeUpdate"));
        this.on("filetreeUpdate", () => {
            log("filetreeUpdate")
        })
        setInterval(() => {
            this.drainMailbox()
        }, 100);
        super.start();
    }
}
