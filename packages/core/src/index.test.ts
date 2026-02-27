import { describe, test, expect } from "bun:test";
import { resolve } from "node:path";
import { CoreLib } from "./index";

const settingsPath = resolve(import.meta.dir, "../../../settings");

describe("CoreLib lifecycle", () => {
    test("init, load settings, and teardown without errors", () => {
        const core = new CoreLib();

        const monitor = core.createMonitor();
        expect(monitor).not.toBeNull();

        const settings = core.createSettings();
        expect(settings).not.toBeNull();

        core.loadSettings(settings!, settingsPath, monitor!);
        core.drainEvents();

        core.destroySettings(settings!);
        core.destroyMonitor(monitor!);
        core.deinitState();
    });
});
