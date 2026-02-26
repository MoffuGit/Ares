import { EventType, resolveCoreLib } from "./index";

const core = resolveCoreLib();

core.events.on(EventType.TestData.toString(), (data) => {
    console.log(`[Zig TestData]: id=${data.id}, allocated=0x${BigInt(data.allocated).toString(16)}`);
    core.destroyAllocated(data.allocated);
    console.log("[Zig TestData]: Allocated destroyed");
});

core.initState();
core.startLoop();

console.log("Zig thread emitting events every 2s, polling every 500ms...");

setInterval(() => {
    core.pollEvents();
}, 500);
