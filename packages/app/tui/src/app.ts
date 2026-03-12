import { CoreApp } from "@ares/shared/core";

export class TuiApp extends CoreApp {
    constructor(settingsPath: string, projectPath: string, libPath?: string,) {
        super(libPath);

        this.loadSettings(settingsPath, this.appearance);
        this.openProject(projectPath);
    }
}
