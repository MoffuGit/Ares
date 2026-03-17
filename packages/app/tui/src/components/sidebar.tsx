import { createContext, createSignal, createMemo, useContext, type JSX, type Accessor } from "solid-js";
import { useTheme } from "@ares/shared/solid";

const SIDEBAR_WIDTH = 28;
const SIDEBAR_WIDTH_ICON = 6;

type SidebarContextProps = {
    state: Accessor<"expanded" | "collapsed">;
    open: Accessor<boolean>;
    setOpen: (open: boolean) => void;
    toggleSidebar: () => void;
};

const SidebarContext = createContext<SidebarContextProps | null>(null);

function useSidebar() {
    const context = useContext(SidebarContext);
    if (!context) {
        throw new Error("useSidebar must be used within a SidebarProvider.");
    }
    return context;
}

function SidebarProvider(props: {
    defaultOpen?: boolean;
    open?: boolean;
    onOpenChange?: (open: boolean | ((prev: boolean) => boolean)) => void;
    children?: JSX.Element;
}) {
    const [_open, _setOpen] = createSignal(props.defaultOpen ?? true);

    const open = () => props.open !== undefined ? props.open : _open();

    const setOpen = (value: boolean | ((prev: boolean) => boolean)) => {
        if (props.onOpenChange) {
            props.onOpenChange(value);
        } else {
            _setOpen(value as any);
        }
    };

    const toggleSidebar = () => setOpen(!open());

    const state = createMemo(() => (open() ? "expanded" : "collapsed") as const);

    const contextValue: SidebarContextProps = {
        state,
        open,
        setOpen,
        toggleSidebar,
    };

    const theme = useTheme();

    return (
        <SidebarContext.Provider value={contextValue}>
            <box bg={theme()?.bg ?? "#1e1e2e"} fg={theme()?.fg ?? "#cdd6f4"} flexDirection="row" flexGrow={1} width={{ percent: 100 }} height={{ percent: 100 }}>
                {props.children}
            </box>
        </SidebarContext.Provider>
    );
}

function Sidebar(props: {
    side?: "left" | "right";
    collapsible?: "icon" | "none";
    children?: JSX.Element;
}) {
    const { open } = useSidebar();
    const theme = useTheme();

    const collapsible = () => props.collapsible ?? "icon";
    const width = () => {
        if (collapsible() === "none") return SIDEBAR_WIDTH;
        return open() ? SIDEBAR_WIDTH : SIDEBAR_WIDTH_ICON;
    };

    return (
        <box
            bg={theme()?.sidebar ?? "#1e1e2e"}
            fg={theme()?.sidebarFg ?? "#cdd6f4"}
            flexDirection="column"
            width={{ point: width() }}
            height={{ percent: 100 }}
            display={open() ? "flex" : "none"}
        >
            {props.children}
        </box>
    );
}

function SidebarTrigger(props: {
    children?: JSX.Element;
}) {
    const { toggleSidebar } = useSidebar();
    const theme = useTheme();

    return (
        <box on:click={() => toggleSidebar()} bg={theme()?.sidebarAccent ?? "#313244"} fg={theme()?.sidebarAccentFg ?? "#cdd6f4"} width={{ point: 3 }}>
            {props.children ?? "☰"}
        </box>
    );
}

function SidebarInset(props: {
    children?: JSX.Element;
}) {
    const theme = useTheme();

    return (
        <box bg={theme()?.mutedBg ?? "#181825"} fg={theme()?.fg ?? "#cdd6f4"} flexDirection="column" flexGrow={1}>
            {props.children}
        </box>
    );
}

function SidebarHeader(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="column" padding={{ all: { point: 1 } }}>
            {props.children}
        </box>
    );
}

function SidebarFooter(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="column" padding={{ all: { point: 1 } }}>
            {props.children}
        </box>
    );
}

function SidebarContent(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="column" flexGrow={1} overflow="scroll">
            {props.children}
        </box>
    );
}

function SidebarGroup(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="column" width={{ percent: 100 }}>
            {props.children}
        </box>
    );
}

function SidebarGroupLabel(props: {
    children?: JSX.Element;
}) {
    const { open } = useSidebar();

    return (
        <box
            height={{ point: 1 }}
            padding={{ horizontal: { point: 1 } }}
            display={open() ? "flex" : "none"}
        >
            {props.children}
        </box>
    );
}

function SidebarGroupAction(props: {
    children?: JSX.Element;
}) {
    const { open } = useSidebar();

    return (
        <box display={open() ? "flex" : "none"}>
            {props.children}
        </box>
    );
}

function SidebarGroupContent(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="column" width={{ percent: 100 }}>
            {props.children}
        </box>
    );
}

function SidebarMenu(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="column" width={{ percent: 100 }}>
            {props.children}
        </box>
    );
}

function SidebarMenuItem(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="row" width={{ percent: 100 }}>
            {props.children}
        </box>
    );
}

function SidebarMenuButton(props: {
    isActive?: boolean;
    children?: JSX.Element;
    onClick: () => void;
}) {
    return (
        <box
            on:click={props.onClick}
            flexDirection="row"
            width={{ percent: 100 }}
            height={{ point: 1 }}
            padding={{ horizontal: { point: 1 } }}
        >
            {props.children}
        </box>
    );
}

function SidebarMenuAction(props: {
    children?: JSX.Element;
}) {
    const { open } = useSidebar();

    return (
        <box display={open() ? "flex" : "none"}>
            {props.children}
        </box>
    );
}

function SidebarMenuBadge(props: {
    children?: JSX.Element;
}) {
    const { open } = useSidebar();

    return (
        <box display={open() ? "flex" : "none"}>
            {props.children}
        </box>
    );
}

function SidebarMenuSub(props: {
    children?: JSX.Element;
}) {
    const { open } = useSidebar();

    return (
        <box
            flexDirection="column"
            padding={{ left: { point: 1 } }}
            display={open() ? "flex" : "none"}
        >
            {props.children}
        </box>
    );
}

function SidebarMenuSubItem(props: {
    children?: JSX.Element;
}) {
    return (
        <box flexDirection="row">
            {props.children}
        </box>
    );
}

function SidebarMenuSubButton(props: {
    isActive?: boolean;
    children?: JSX.Element;
}) {
    return (
        <box
            flexDirection="row"
            height={{ point: 1 }}
            padding={{ horizontal: { point: 1 } }}
        >
            {props.children}
        </box>
    );
}

function SidebarSeparator() {
    return (
        <box
            height={{ point: 1 }}
            width={{ percent: 100 }}
            margin={{ horizontal: { point: 1 } }}
        >
            {"─".repeat(40)}
        </box>
    );
}

export {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupAction,
    SidebarGroupContent,
    SidebarGroupLabel,
    SidebarHeader,
    SidebarInset,
    SidebarMenu,
    SidebarMenuAction,
    SidebarMenuBadge,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarMenuSub,
    SidebarMenuSubButton,
    SidebarMenuSubItem,
    SidebarProvider,
    SidebarSeparator,
    SidebarTrigger,
    useSidebar,
};
