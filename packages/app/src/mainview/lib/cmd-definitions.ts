import type { Mode } from "@ares/shared";

export type FlatCmdEntry = {
    readonly search: boolean;
    readonly title: string;
    readonly mode: Mode | readonly Mode[];
};

export const cmdDefinitions = {
    global: {
        enterInsert:          { search: false, title: "Enter insert mode",      mode: ["normal", "visual"] },
        enterVisual:          { search: false, title: "Enter visual mode",      mode: "normal" },
        enterNormal:          { search: false, title: "Enter normal mode",      mode: ["insert", "visual"] },
        toggleLeftSidebar:    { search: true,  title: "Toggle left sidebar",    mode: ["normal", "insert", "visual"] },
        newTab:               { search: true,  title: "New tab",                mode: ["normal", "insert", "visual"] },
        nextTab:              { search: false, title: "Next tab",               mode: ["normal", "insert", "visual"] },
        prevTab:              { search: false, title: "Previous tab",           mode: ["normal", "insert", "visual"] },
        closeActiveTab:       { search: true,  title: "Close active tab",       mode: ["normal", "insert", "visual"] },
        toggleCommandPalette: { search: false, title: "Toggle command palette", mode: ["normal", "insert", "visual"] },
        tabsPanel:            { search: true,  title: "Show tabs panel",        mode: ["normal", "insert", "visual"] },
        filetreePanel:        { search: true,  title: "Show filetree panel",    mode: ["normal", "insert", "visual"] },
        newTerminalTab:       { search: true,  title: "New terminal tab",       mode: ["normal", "insert", "visual"] },
        toggleCmd:            { search: false, title: "Toggle cmd",             mode: ["normal", "insert", "visual"] },
    },
} as const satisfies Record<string, Record<string, FlatCmdEntry>>;

type CmdDefinitions = typeof cmdDefinitions;
type Entries<S extends CmdScope> = CmdDefinitions[S];

export type CmdScope = keyof CmdDefinitions & string;
export type CmdKey<S extends CmdScope> = keyof Entries<S> & string;
export type CmdId<S extends CmdScope = CmdScope> = `${S}:${CmdKey<S>}`;

type NormalizeMode<M> =
    M extends readonly Mode[] ? M
    : M extends Mode ? readonly [M]
    : never;

type ResolvedCmd<S extends CmdScope, K extends CmdKey<S>> = {
    readonly scope: S;
    readonly key: K;
    readonly id: `${S}:${K}`;
    readonly search: Entries<S>[K] extends { search: infer X } ? X : never;
    readonly title: Entries<S>[K] extends { title: infer X } ? X : never;
    readonly mode: Entries<S>[K] extends { mode: infer M } ? NormalizeMode<M> : never;
};

export type ScopeCmdDefinition<S extends CmdScope = CmdScope> = {
    [K in CmdKey<S>]: ResolvedCmd<S, K>;
}[CmdKey<S>];

export type ScopeCmdsByKey<S extends CmdScope = CmdScope> = {
    readonly [K in CmdKey<S>]: ResolvedCmd<S, K>;
};

export type ScopeCmdsById<S extends CmdScope = CmdScope> = {
    readonly [K in CmdKey<S> as `${S}:${K}`]: ResolvedCmd<S, K>;
};

export type GlobalCmdKey = CmdKey<"global">;
export type GlobalCmdId = CmdId<"global">;
export type GlobalCmdDefinition = ScopeCmdDefinition<"global">;

function normalizeMode(mode: Mode | readonly Mode[]): readonly Mode[] {
    return Array.isArray(mode) ? mode : [mode as Mode];
}

type AllScopeCmdsByKey = { readonly [S in CmdScope]: ScopeCmdsByKey<S> };
type AllScopeCmdsById  = { readonly [S in CmdScope]: ScopeCmdsById<S> };

function buildIndexes(): { byKey: AllScopeCmdsByKey; byId: AllScopeCmdsById } {
    const byKey: Record<string, Record<string, unknown>> = {};
    const byId: Record<string, Record<string, unknown>> = {};

    for (const scope of Object.keys(cmdDefinitions) as CmdScope[]) {
        const scopeByKey: Record<string, unknown> = {};
        const scopeById: Record<string, unknown> = {};
        const entries = cmdDefinitions[scope] as Record<string, FlatCmdEntry>;

        for (const key of Object.keys(entries)) {
            const entry = entries[key];
            const id = `${scope}:${key}`;
            const resolved = {
                scope,
                key,
                id,
                search: entry.search,
                title: entry.title,
                mode: normalizeMode(entry.mode),
            };
            scopeByKey[key] = resolved;
            scopeById[id] = resolved;
        }

        byKey[scope] = scopeByKey;
        byId[scope] = scopeById;
    }

    return {
        byKey: byKey as unknown as AllScopeCmdsByKey,
        byId: byId as unknown as AllScopeCmdsById,
    };
}

const indexes = buildIndexes();
export const scopeCmdsByKey = indexes.byKey;
export const scopeCmdsById = indexes.byId;

export const globalCmds = scopeCmdsByKey.global;

export function isCmdAllowedInMode(
    def: { readonly mode: readonly Mode[] },
    mode: Mode,
): boolean {
    return def.mode.includes(mode);
}

export function resolveScopeCmdDefinition<S extends CmdScope>(
    scope: S,
    mode: Mode,
    cmdId: string,
): ScopeCmdDefinition<S> | null {
    const byId = scopeCmdsById[scope] as Record<string, ScopeCmdDefinition<S> | undefined>;
    const cmd = byId[cmdId];
    if (!cmd) return null;
    if (!isCmdAllowedInMode(cmd, mode)) return null;
    return cmd;
}
