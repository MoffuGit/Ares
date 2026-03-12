import { CoreApp } from "@ares/core/app";
import type { Pointer } from "bun:ffi";

export class DesktopApp extends CoreApp {
    private appearance: Pointer | null = null;
    constructor(settingsPath: string, projectPath: string, libPath?: string,) {
        super(libPath);

        this.appearance = this.core.createAppearance();

        this.loadSettings(settingsPath, this.appearance);
        this.openProject(projectPath);
    }

    stop() {
        if (this.appearance) this.core.destroyAppearance(this.appearance);
        super.stop();
    }
}
