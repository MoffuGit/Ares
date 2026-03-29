---
name: adding-settings-field
description: "Adds a new settings field across the full Zig→TS pipeline. Use when asked to add a setting, preference, or config option to the app."
---

# Adding a Settings Field

Adds a new user-facing setting across all layers: Zig core parsing, FFI extern struct, TS FFI struct, shared types, App class, and zustand store.

## Checklist

Work through each step in order. The field name below uses `my_field` (snake_case) as a placeholder — substitute the real name.

### 1. Zig enum (if the field is an enum)

**File:** `core/settings/mod.zig`

Add the enum next to the existing `Scheme` / `ColorScheme` / `TabsPosition` enums:

```zig
pub const MyField = enum { option_a, option_b };
```

### 2. Zig JSON input struct

**File:** `core/settings/mod.zig` — `JsonSettings`

Add the field with a sensible default so existing `settings.json` files don't break:

```zig
my_field: []const u8 = "option_a",
```

For non-string types (bool, integer) use the native type directly instead of `[]const u8`.

### 3. Zig Settings struct

**File:** `core/settings/mod.zig` — `Settings` (the `@This()` struct)

Add the runtime field:

```zig
my_field: MyField = .option_a,
```

### 4. Zig parsing

**File:** `core/settings/mod.zig` — `loadSettings()`

Parse after the existing `self.scheme = …` line:

```zig
self.my_field = std.meta.stringToEnum(MyField, json_settings.my_field) orelse .option_a;
```

For booleans or integers, assign directly instead of using `stringToEnum`.

### 5. Zig extern struct

**File:** `core/lib.zig` — `ExternSettings`

Add the field. Use `u64` for enums, `u8` for bools, matching the existing pattern:

```zig
my_field: u64,
```

**Placement matters** — the field order in `ExternSettings` must match the TS `defineStruct` order exactly.

### 6. Zig readSettings export

**File:** `core/lib.zig` — `readSettings()`

Populate the new field:

```zig
.my_field = @intFromEnum(settings.my_field),
```

### 7. TS FFI struct

**File:** `packages/core/src/structs.ts`

If the field is an enum, define it and add to the `Settings` struct. The enum values must match the Zig enum ordinal order:

```ts
const MyField = defineEnum({ option_a: 0, option_b: 1 }, "u64");

// Inside the Settings defineStruct array, in the same position as the extern struct:
["my_field", MyField],
```

For booleans use `"bool_u8"`, for integers use `"u64"` / `"u32"` etc.

### 8. TS shared types

**File:** `packages/app/shared/src/types.ts`

Add the TS type (for enums, use a string union):

```ts
export type MyField = "option_a" | "option_b";
```

Add the field to the `Settings` type:

```ts
export type Settings = {
    // …existing fields…
    my_field: MyField;
};
```

### 9. App class readSettings

**File:** `packages/app/shared/src/app/index.ts` — `readSettings()`

Add the field to the returned object:

```ts
return {
    // …existing fields…
    my_field: raw.my_field,
};
```

### 10. Zig tests

**File:** `core/settings/mod.zig` — update the test JSON and add an assertion:

```zig
// In the test JSON string, add the new field:
\\{"appearance":"dark","light_theme":"my_light","dark_theme":"my_dark","my_field":"option_b"}

// Add assertion:
try std.testing.expectEqual(MyField.option_b, self.my_field);
```

## What you DON'T need to change

These files use the `Settings` type and pick up new fields automatically:

- `packages/app/desktop/src/rpc.ts` — RPC schema references `Settings`
- `packages/app/desktop/src/bun/index.ts` — forwards `app._state.settings`
- `packages/app/desktop/src/mainview/lib/app.ts` — zustand store receives `Settings` via RPC

## Key rules

- **Enum ordinals must match** between Zig `enum` variant order, `ExternSettings` integer values, and TS `defineEnum` values.
- **Extern struct field order must match** between Zig `ExternSettings` and TS `defineStruct`.
- **Always provide a default** in `JsonSettings` so existing `settings.json` files without the new field still parse.
- **Naming:** Zig and FFI use `snake_case`. TS types can use either `snake_case` (matching FFI) or `camelCase` — follow the existing convention in `Settings` which currently uses `snake_case`.
