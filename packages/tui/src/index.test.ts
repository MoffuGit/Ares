import { describe, test, expect } from "bun:test";
import { TuiLib } from "./index";

describe("TuiLib lifecycle", () => {
    test("init, load, and teardown", () => {
        const core = new TuiLib();

        const app = core.createApp();
        expect(app).not.toBeNull();
        core.destroyApp(app!);
        core.deinitState();
    });
});
