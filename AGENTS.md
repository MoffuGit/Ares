# Ares – Adding Events & State Pipeline

## Architecture Overview

The system has 5 layers. Events flow Zig → TS FFI → App class → Desktop RPC → Webview store.

```
Zig core (core/)
  ↓  mailbox + C callback
TS FFI bindings (packages/core/src/)
  ↓  EventEmitter
Shared App class (packages/app/shared/src/app/)
  ↓  EventEmitter
Desktop RPC + bun entry (packages/app/desktop/src/bun/ + rpc.ts)
  ↓  electrobun RPC
Webview store (packages/app/desktop/src/mainview/lib/app.ts)
```

## Two Event Systems in Zig

There are two separate event systems — don't confuse them:

1. **`GlobalEvents`** (`core/global.zig`): Synchronous in-process events dispatched via `global.state.emitGlobal()`. Used for internal Zig-side communication (e.g., `Editor` listens to `bufferUpdate` to re-render its surface). These do NOT cross the FFI boundary.

2. **`Events`** (`core/global.zig`): Mailbox events pushed via `global.state.emit()`. These are the events that cross the FFI boundary to TypeScript via the `drainMailbox` callback. The TS side polls `drainMailbox()` on an interval.

When something happens (e.g., a buffer finishes loading), the source typically emits BOTH:
```zig
// core/buffer/BufferStore.zig – readCallback
global.state.emitGlobal(.{ .bufferUpdate = buf.entry_id });           // internal
global.state.emit(.{ .bufferUpdate = .{                                // to JS
    .entry_id = buf.entry_id,
    .row_count = buf.text.rowCount,
} }, .instant);
```

## How Event Notification + Data Works

### Signal-only events (no data)

For events that just signal "something changed" (e.g., `settingsUpdate`, `themeUpdate`, `filetreeUpdate`):

- **Zig**: The `Events` variant has payload `void`. In `drainMailbox`, it calls `cb(@intFromEnum(ev), null, 0)`.
- **TS FFI**: `Events[type]` is `null` in `events.ts`, so the callback emits the event name with no data.
- **App class**: Listens and calls a read function to pull fresh state (e.g., `readSettings()`, `readFiletree()`).

### Data-carrying events (inline struct)

For events that carry data across the FFI boundary (e.g., `bufferUpdate`):

- **Zig**: The `Events` variant carries an `extern struct` payload (e.g., `bufferUpdate: ExternBufferState`). The struct is embedded directly in the union. In `drainMailbox`, it passes a pointer to the struct data: `cb(@intFromEnum(ev), @ptrCast(&bs), @sizeOf(global.ExternBufferState))`.
- **TS FFI**: `Events[type]` points to the corresponding `defineStruct(...)` in `structs.ts`. The callback unpacks with `toArrayBuffer(ptr, 0, len)` + `struct.unpack()` and emits the event with the unpacked data.
- **App class**: Listens and receives the data directly — no separate read call needed.

## Step-by-Step: Adding a New Event

### 1. Zig Core (`core/global.zig`)

Add the variant to the `Events` union. Choose the right payload:

```zig
pub const Events = union(enum) {
    settingsUpdate: void,          // signal-only
    themeUpdate: void,             // signal-only
    filetreeUpdate: void,          // signal-only
    bufferUpdate: ExternBufferState, // data-carrying
    myNewEvent: void,              // ← add here (or with an extern struct)
};
```

**If data-carrying**, define the extern struct in `core/global.zig`:

```zig
pub const ExternMyData = extern struct {
    some_id: u64,
    some_value: u32,
};
```

**IMPORTANT**: The ordinal position in `Events` determines the integer value sent to JS. New variants MUST be appended at the end, or you must update the TS `EventType` enum to match.

### 2. Zig Core (`core/lib.zig`) – drainMailbox

Add a case to the `drainMailbox` switch:

```zig
// Signal-only:
.myNewEvent => cb(@intFromEnum(ev), null, 0),

// Data-carrying:
.myNewEvent => |data| {
    cb(@intFromEnum(ev), @ptrCast(&data), @sizeOf(global.ExternMyData));
},
```

### 3. Zig Core – Emit the Event

From wherever the event originates, push to the mailbox:

```zig
// Signal-only:
global.state.emit(.myNewEvent, .instant);

// Data-carrying:
global.state.emit(.{ .myNewEvent = .{
    .some_id = id,
    .some_value = val,
} }, .instant);
```

If internal Zig components also need to react, add a corresponding variant to `GlobalEvents` and emit via `global.state.emitGlobal()` as well.

### 4. TS FFI Structs (`packages/core/src/structs.ts`)

**Only for data-carrying events.** Define the struct matching the Zig extern struct:

```ts
export const MyData = defineStruct([
    ["some_id", "u64"],
    ["some_value", "u32"],
] as const);
```

### 5. TS FFI Events (`packages/core/src/events.ts`)

Add to `EventType` (ordinal MUST match Zig `Events` union order), `EventsName`, and `Events`:

```ts
export enum EventType {
    SettingsUpdate,   // 0
    ThemeUpdate,      // 1
    FiletreeUpdate,   // 2
    BufferUpdate,     // 3
    MyNewEvent,       // 4 ← must match position in Zig Events union
}

export const EventsName: Record<EventType, string> = {
    // ...existing...
    [EventType.MyNewEvent]: "MyNewEvent",
};

export const Events: Record<EventType, StructDef<any> | null> = {
    // ...existing...
    [EventType.MyNewEvent]: null,        // signal-only
    // [EventType.MyNewEvent]: MyData,   // data-carrying
};
```

### 6. TS FFI CoreLib (`packages/core/src/index.ts`)

**Only if the event needs a state-reading function** (typically for signal-only events where the App needs to pull state). Add the FFI symbol declaration and a wrapper method:

```ts
// In getCoreLib symbols:
readMyData: {
    args: [FFIType.pointer, FFIType.pointer],
    returns: FFIType.bool,
},

// In CoreLib class:
readMyData(somePtr: Pointer): { some_id: number; some_value: number } | null {
    const buf = new ArrayBuffer(MyData.size);
    const ok = this.lib.symbols.readMyData(somePtr, ptr(buf));
    if (!ok) return null;
    const raw = MyData.unpack(buf);
    return { some_id: Number(raw.some_id), some_value: Number(raw.some_value) };
}
```

The callback in `initState()` handles dispatch automatically — no changes needed there. It checks `Events[type]`: if `null`, emits event name only; if a struct, unpacks and emits with data.

### 7. Shared Types (`packages/app/shared/src/types.ts`)

Add the TS type and update `AppEvents`:

```ts
export type MyData = {
    someId: number;   // camelCase in TS
    someValue: number;
};

export type AppEvents = {
    // ...existing...
    myNewEvent: [data: MyData];  // or [] for signal-only
};
```

### 8. Shared App Class (`packages/app/shared/src/app/index.ts`)

Register the listener in `start()`, clean up in `stop()`, and re-emit:

```ts
// In start():
this.core.on("MyNewEvent", this.onMyNewEvent);

// In stop():
this.core.off("MyNewEvent", this.onMyNewEvent);

// Handler (data-carrying):
protected onMyNewEvent = ({ some_id, some_value }: { some_id: number | bigint; some_value: number | bigint }) => {
    const someId = typeof some_id === "bigint" ? Number(some_id) : some_id;
    const someValue = typeof some_value === "bigint" ? Number(some_value) : some_value;
    this.emit("myNewEvent", { someId, someValue } as MyData);
};

// Handler (signal-only — pull state):
protected onMyNewEvent = () => {
    // optionally read state, update this._state
    this.emit("myNewEvent");
};
```

**Convention**: CoreLib events use PascalCase (`"MyNewEvent"`). App events use camelCase (`"myNewEvent"`). Zig extern structs use snake_case, TS types use camelCase — the App layer does the mapping.

### 9. Desktop RPC Schema (`packages/app/desktop/src/rpc.ts`)

Add to the `webview.messages`:

```ts
webview: RPCSchema<{
    requests: {};
    messages: {
        // ...existing...
        myNewEvent: MyData;  // or just a signal type
    };
}>;
```

### 10. Desktop Bun Entry (`packages/app/desktop/src/bun/index.ts`)

Wire the App event to an RPC send:

```ts
app.on("myNewEvent", (data) => {
    mainWindow.webview.rpc?.send.myNewEvent(data);
});
```

### 11. Webview Store (`packages/app/desktop/src/mainview/lib/app.ts`)

Handle the incoming RPC message and update zustand state:

```ts
// In rpc message handlers:
myNewEvent: (data) => {
    useAppStore.setState({ /* update relevant state */ });
},
```

## Key Constraints

- **Ordinal matching**: `EventType` enum values in TS MUST match the variant order in Zig `Events` union(enum). Always append new variants at the end of both.
- **Event flow**: Consumers listen to `App` events, never directly to `CoreLib` events.
- **Naming**: Zig `snake_case` → TS FFI `snake_case` (raw) → App/types `camelCase`. CoreLib event names are `PascalCase`, App event names are `camelCase`.
- **BigInt handling**: `u64` fields from FFI may arrive as `bigint`. Always convert with `Number()` in the App layer handler.
- **Extern struct alignment**: Zig `extern struct` and `defineStruct` field order and types must match exactly. Use `u64`, `u32`, `u8`, etc. — not Zig-native types.
- **Mutex discipline**: State-reading exports in `lib.zig` that access shared data must lock/unlock the appropriate mutex. Provide `lockX`/`unlockX` exports if the TS side needs to hold a lock across multiple reads.
