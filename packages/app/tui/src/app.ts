import { CoreApp } from "@ares/shared/core";

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
        this.on("modeUpdate", () => this.events.emit("modeUpdate"));
        this.on("keymapsUpdate", () => this.events.emit("keymapsUpdate"));
        setInterval(() => {
            this.drainMailbox()
        }, 100);
        super.start();
    }
}
