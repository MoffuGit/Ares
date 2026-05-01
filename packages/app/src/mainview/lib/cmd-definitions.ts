export type CmdScope = string;

export type BaseScopeCmdDefinition<Scope extends CmdScope = CmdScope, Id extends string = string> = {
    scope: Scope;
    id: Id;
};

export const globalScopeCmdDefinitions = {
    enterInsert: { scope: "global", id: "workspace:enter_insert" },
    enterVisual: { scope: "global", id: "workspace:enter_visual" },
    enterNormal: { scope: "global", id: "workspace:enter_normal" },
    toggleLeftSidebar: { scope: "global", id: "workspace:toggle_left_sidebar" },
    newTab: { scope: "global", id: "workspace:new_tab" },
    nextTab: { scope: "global", id: "workspace:next_tab" },
    prevTab: { scope: "global", id: "workspace:prev_tab" },
    closeActiveTab: { scope: "global", id: "workspace:close_active_tab" },
    toggleCommandPalette: { scope: "global", id: "workspace:toggle_command_palette" },
    tabsPanel: { scope: "global", id: "workspace:tabs_panel" },
    filetreePanel: { scope: "global", id: "workspace:filetree_panel" },
    newTerminalTab: { scope: "global", id: "workspace:new_terminal_tab" },
    toggleCmd: { scope: "global", id: "workspace:toggle_cmd" },
} as const satisfies Record<string, BaseScopeCmdDefinition<"global">>;

export type GlobalScopeCmdDefinition = typeof globalScopeCmdDefinitions[keyof typeof globalScopeCmdDefinitions];
export type GlobalScopeCmdId = GlobalScopeCmdDefinition["id"];

const globalScopeCmdDefinitionsById = {
    [globalScopeCmdDefinitions.enterInsert.id]: globalScopeCmdDefinitions.enterInsert,
    [globalScopeCmdDefinitions.enterVisual.id]: globalScopeCmdDefinitions.enterVisual,
    [globalScopeCmdDefinitions.enterNormal.id]: globalScopeCmdDefinitions.enterNormal,
    [globalScopeCmdDefinitions.toggleLeftSidebar.id]: globalScopeCmdDefinitions.toggleLeftSidebar,
    [globalScopeCmdDefinitions.newTab.id]: globalScopeCmdDefinitions.newTab,
    [globalScopeCmdDefinitions.nextTab.id]: globalScopeCmdDefinitions.nextTab,
    [globalScopeCmdDefinitions.prevTab.id]: globalScopeCmdDefinitions.prevTab,
    [globalScopeCmdDefinitions.closeActiveTab.id]: globalScopeCmdDefinitions.closeActiveTab,
    [globalScopeCmdDefinitions.toggleCommandPalette.id]: globalScopeCmdDefinitions.toggleCommandPalette,
    [globalScopeCmdDefinitions.tabsPanel.id]: globalScopeCmdDefinitions.tabsPanel,
    [globalScopeCmdDefinitions.filetreePanel.id]: globalScopeCmdDefinitions.filetreePanel,
    [globalScopeCmdDefinitions.newTerminalTab.id]: globalScopeCmdDefinitions.newTerminalTab,
    [globalScopeCmdDefinitions.toggleCmd.id]: globalScopeCmdDefinitions.toggleCmd,
} as const satisfies Record<GlobalScopeCmdId, GlobalScopeCmdDefinition>;

export type ScopeCmdDefinitionsByScope = {
    global: GlobalScopeCmdDefinition;
};

export type ScopeCmdDefinition<Scope extends CmdScope = CmdScope> =
    Scope extends keyof ScopeCmdDefinitionsByScope
        ? ScopeCmdDefinitionsByScope[Scope]
        : BaseScopeCmdDefinition<Scope>;

export function resolveScopeCmdDefinition(scope: "global", cmd: string): GlobalScopeCmdDefinition | null;
export function resolveScopeCmdDefinition<Scope extends CmdScope>(scope: Scope, cmd: string): ScopeCmdDefinition<Scope>;
export function resolveScopeCmdDefinition<Scope extends CmdScope>(scope: Scope, cmd: string) {
    switch (scope) {
        case "global":
            return globalScopeCmdDefinitionsById[cmd as GlobalScopeCmdId] ?? null;
        default:
            return { scope, id: cmd } as ScopeCmdDefinition<Scope>;
    }
}
