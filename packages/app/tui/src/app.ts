import { CoreApp } from "@ares/core/app";

export class TuiApp extends CoreApp {
    constructor(settingsPath: string, projectPath: string, libPath?: string,) {
        super(libPath);
    }
}
