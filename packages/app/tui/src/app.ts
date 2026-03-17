import { CoreApp } from "@ares/shared/core";

export class TuiApp extends CoreApp {
    constructor(settingsPath: string, projectPath: string, libPath?: string,) {
        super(libPath);

        this.loadSettings(settingsPath, null);
        this.openProject(projectPath);
    }

    override start() {
        setInterval(() => {
            this.drainMailbox()
        }, 100);
        super.start();
    }
}
