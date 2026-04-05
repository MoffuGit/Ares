import { Electroview } from "electrobun/view";
import type { Mode, WorktreeEntry, Tab, Surface, SidebarKind, Settings, Theme, Project } from "@ares/shared";
import { canUseSidebarKind, surfaceName } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";
import { create } from "zustand";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
    filetree: WorktreeEntry[] | null;
    mode: Mode;
    project: Project | null;

    sidebarOpen: boolean;
    sidebarKind: SidebarKind;

    tabs: Tab[];
    activeTabId: number | null;
};

interface AppStore extends AppState {
    setMode: (mode: Mode) => void;
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
    sidebarKind: "filetree",
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
                ? { ...t, name: entry.name, surface: { ...t.surface, entry: entry } } : t)
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
        const { settings, theme } = await rpc.request.initialLoad({});
        set({
            settings: settings,
            theme: theme,
        });
    },

    openProjectDialog: async () => {
        try {
            const project = await rpc.request.openProjectDialog({});
            if (!project) return;
            set({ project, sidebarKind: "filetree" });
        } catch (error) {
            console.error("openProjectDialog failed", error);
        }
    },
}));

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
            bufferUpdate: (bufferState) => {
                const tabs = useAppStore.getState().tabs.map((t) => {
                    if (t.surface.kind === "editor" && t.surface.entry?.id === bufferState.entryId) {
                        return { ...t, surface: { ...t.surface, bufferState } };
                    }
                    return t;
                });
                useAppStore.setState({ tabs });
            },
        },
    },
});

export { rpc };
