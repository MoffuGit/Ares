import { describe, test, expect } from "bun:test";
import { resolve } from "node:path";
import { CoreLib } from "./index";

const settingsPath = resolve(import.meta.dir, "../../../settings");

//NOTE:
//this fail with this:
//index.test.ts:
// debug(monitor): starting monitor thread
// fish: Job 1, 'bun test' terminated by signal SIGTRAP (Trace or breakpoint trap)
describe("CoreLib lifecycle", () => {
    test("init, load, and teardown", () => {
        const core = new CoreLib();

        const monitor = core.createMonitor();
        expect(monitor).not.toBeNull();

        const settings = core.createSettings();
        expect(settings).not.toBeNull();

        core.loadSettings(settings!, settingsPath, monitor!);

        //BUG:
        const settingsData = core.readSettings(settings!);
        console.log("Settings:", settingsData);

        core.destroySettings(settings!);
        core.destroyMonitor(monitor!);
        core.deinitState();
    });
});
