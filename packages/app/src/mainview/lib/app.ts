import { Electroview } from "electrobun/view";
import type { EditorState, Mode, SurfaceState, WorktreeEntry, Tab, Surface, SidebarKind, Settings, Theme, Project } from "@ares/shared";
import { canUseSidebarKind, surfaceName } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";
import { create } from "zustand";
import { cmdEventEmitter } from "./cmd-event-emitter.ts";
import { globalScopeCmdDefinitions, type GlobalScopeCmdDefinition } from "./cmd-definitions.ts";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
    filetree: WorktreeEntry[] | null;
    mode: Mode;
    project: Project | null;

    sidebarOpen: boolean;
    sidebarKind: SidebarKind;

    cmdOpen: boolean;

    tabs: Tab[];
    activeTabId: number | null;
};

interface AppStore extends AppState {
    setMode: (mode: Mode) => void;
    handleGlobalCmd: (cmd: GlobalScopeCmdDefinition) => void;
    initialLoad: () => Promise<void>;
    openProjectDialog: () => Promise<void>;
    expandEntry: (entry: WorktreeEntry) => void;
    selectSurfaceEntry: (entry: WorktreeEntry) => void;
    newTab: (surface: Surface) => void;
    closeTab: (tabId: number) => void;
    setActiveTab: (tabId: number) => void;
    setGpuSurfaceId: (tabId: number, gpuSurfaceId: number) => void;
    nextTab: () => void;
    prevTab: () => void;

    setSidebarOpen: (open: boolean) => void;
    toggleSidebarKind: (kind: SidebarKind) => void;
    toggleSidebar: () => void;
    toggleCmd: () => void;
    setCmdOpen: (open: boolean) => void;
}


export const useAppStore = create<AppStore>((set, get) => ({
    settings: null,
    theme: null,
    filetree: null,
    mode: "normal",
    project: null,
    tabs: [],
    activeTabId: null,
    sidebarOpen: false,
    cmdOpen: false,
    sidebarKind: "filetree",

    toggleCmd: () => set((s) => ({ cmdOpen: !s.cmdOpen })),
    setCmdOpen: (open) => set({ cmdOpen: open }),

    setSidebarOpen: (open) => set({ sidebarOpen: open }),
    toggleSidebarKind: (kind) => set((state) => {
        if (!state.settings) return {};
        if (!canUseSidebarKind(state.settings, kind)) return {};

        if (!state.sidebarOpen) {
            return { sidebarOpen: true, sidebarKind: kind };
        }

        if (state.sidebarKind !== kind) {
            return { sidebarKind: kind };
        }

        return { sidebarOpen: false };
    }),
    toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),

    setMode: (mode) => {
        if (get().mode === mode) return;
        set({ mode: mode });
        rpc.send("setMode", mode);
    },

    handleGlobalCmd: (cmd) => {
        switch (cmd.id) {
            case globalScopeCmdDefinitions.enterInsert.id:
                get().setMode("insert");
                return;
            case globalScopeCmdDefinitions.enterVisual.id:
                get().setMode("visual");
                return;
            case globalScopeCmdDefinitions.enterNormal.id:
                get().setMode("normal");
                return;
            case globalScopeCmdDefinitions.toggleLeftSidebar.id:
                get().toggleSidebar();
                return;
            case globalScopeCmdDefinitions.newTab.id:
                get().newTab({ kind: "editor" });
                return;
            case globalScopeCmdDefinitions.nextTab.id:
                get().nextTab();
                return;
            case globalScopeCmdDefinitions.prevTab.id:
                get().prevTab();
                return;
            case globalScopeCmdDefinitions.closeActiveTab.id: {
                const activeTabId = get().activeTabId;
                if (activeTabId != null) {
                    get().closeTab(activeTabId);
                }
                return;
            }
            case globalScopeCmdDefinitions.toggleCommandPalette.id:
            case globalScopeCmdDefinitions.toggleCmd.id:
                get().toggleCmd();
                return;
            case globalScopeCmdDefinitions.tabsPanel.id:
                set((state) => {
                    if (!state.settings || !canUseSidebarKind(state.settings, "tabs")) return {};
                    return { sidebarOpen: true, sidebarKind: "tabs" };
                });
                return;
            case globalScopeCmdDefinitions.filetreePanel.id:
                set({ sidebarOpen: true, sidebarKind: "filetree" });
                return;
            case globalScopeCmdDefinitions.newTerminalTab.id:
                get().newTab({ kind: "terminal", cwd: get().project?.path ?? "" });
                return;
        }

        const exhaustiveCheck: never = cmd.id;
        return exhaustiveCheck;
    },

    expandEntry: (entry) => {
        if (entry.kind == "dir") {
            rpc.send("expandEntry", entry.id);
        }
    },

    selectSurfaceEntry: (entry) => {
        const { activeTabId, tabs } = get();
        const activeTab = tabs.find((t) => t.id === activeTabId);
        if (!activeTab || activeTab.surface.kind !== "editor") return;
        if (activeTab.surface.gpuSurfaceId != null) {
            rpc.send("selectSurfaceEntry", { surfaceId: activeTab.surface.gpuSurfaceId, id: entry.id });
        }
        set({
            tabs: tabs.map((t) => t.id === activeTabId && t.surface.kind === "editor"
                ? { ...t, name: entry.name, surface: { ...t.surface, entry: entry, editorState: undefined } } : t)
        });
    },

    newTab: (surface) => {
        const id = Date.now();
        const name = surfaceName(surface);
        const tab: Tab = { id, name, surface: surface };
        const tabs = [...get().tabs, tab];
        set({ tabs, activeTabId: id });
    },

    closeTab: (tabId) => {
        const { tabs, activeTabId } = get();
        const idx = tabs.findIndex((t) => t.id === tabId);
        if (idx === -1) return;
        const tab = tabs[idx];
        if (tab.surface.gpuSurfaceId != null) {
            rpc.send("gpuTagStop", { id: tab.surface.gpuSurfaceId });
        }
        const next = tabs.filter((t) => t.id !== tabId);
        let nextActiveId: number | null = null;
        if (next.length > 0 && activeTabId === tabId) {
            nextActiveId = next[Math.min(idx, next.length - 1)].id;
        } else if (next.length > 0) {
            nextActiveId = activeTabId;
        }
        set({ tabs: next, activeTabId: nextActiveId });
    },

    setActiveTab: (tabId) => {
        set({ activeTabId: tabId });
    },

    setGpuSurfaceId: (tabId, gpuSurfaceId) => {
        const tabs = get().tabs.map((t) =>
            t.id === tabId ? { ...t, surface: { ...t.surface, gpuSurfaceId } } : t
        );
        set({ tabs });
    },

    nextTab: () => {
        const { tabs, activeTabId } = get();
        if (tabs.length === 0) return;
        const idx = tabs.findIndex((t) => t.id === activeTabId);
        set({ activeTabId: tabs[(idx + 1) % tabs.length].id });
    },

    prevTab: () => {
        const { tabs, activeTabId } = get();
        if (tabs.length === 0) return;
        const idx = tabs.findIndex((t) => t.id === activeTabId);
        set({ activeTabId: tabs[(idx - 1 + tabs.length) % tabs.length].id });
    },

    initialLoad: async () => {
        const { settings, theme, mode } = await rpc.request.initialLoad({});
        set({
            settings: settings,
            theme: theme,
            mode,
        });
    },

    openProjectDialog: async () => {
        try {
            const project = await rpc.request.openProjectDialog({});
            if (!project) return;
            set({ project, sidebarKind: "filetree" });
            get().newTab({ kind: "editor" });
        } catch (error) {
            console.error("openProjectDialog failed", error);
        }
    },
}));

cmdEventEmitter.on("global", (event) => {
    useAppStore.getState().handleGlobalCmd(event.cmd);
    event.stopPropagation();
});

const rpc = Electroview.defineRPC<AppRPC>({
    maxRequestTime: 600000,
    handlers: {
        requests: {},
        messages: {
            settingsUpdate: (settings) => {
                useAppStore.setState({
                    settings,
                    sidebarKind: 'filetree',
                });
            },
            themeUpdate: (theme) => {
                useAppStore.setState({ theme });
            },
            filetreeUpdate: (filetree) => {
                useAppStore.setState({ filetree });
            },
            projectUpdate: (project) => {
                useAppStore.setState({ project });
            },
            surfaceUpdate: ({ surfaceId, state }) => {
                syncSurfaceState(surfaceId, state);
            },
            editorStateUpdate: ({ surfaceId, state }) => {
                syncEditorState(surfaceId, state);
            },
            modeUpdate: (mode) => {
                useAppStore.setState({ mode });
            },
            keymapMatch: ({ sequence }) => {
                const state = useAppStore.getState();
                cmdEventEmitter.emitSequence(sequence, state.settings?.keymaps, state.mode);
            },
        },
    },
});

export { rpc };
export { CmdEvent, CmdEventEmitter, cmdEventEmitter } from "./cmd-event-emitter.ts";
export type { CmdEventInit, CmdEventListener, CmdScope } from "./cmd-event-emitter.ts";
export { globalScopeCmdDefinitions, resolveScopeCmdDefinition } from "./cmd-definitions.ts";
export type { BaseScopeCmdDefinition, GlobalScopeCmdDefinition, ScopeCmdDefinition } from "./cmd-definitions.ts";

function syncSurfaceState(surfaceId: number, surfaceState: SurfaceState) {
    const tabs = useAppStore.getState().tabs.map((tab) => {
        if (tab.surface.gpuSurfaceId !== surfaceId) return tab;
        return { ...tab, surface: { ...tab.surface, surfaceState } };
    });
    useAppStore.setState({ tabs });
}

function syncEditorState(surfaceId: number, editorState: EditorState | null) {
    const tabs = useAppStore.getState().tabs.map((tab) => {
        if (tab.surface.kind !== "editor" || tab.surface.gpuSurfaceId !== surfaceId) return tab;
        return {
            ...tab,
            surface: {
                ...tab.surface,
                editorState: editorState ?? undefined,
            },
        };
    });
    useAppStore.setState({ tabs });
}
