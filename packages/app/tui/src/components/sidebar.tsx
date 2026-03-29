import { createContext, createSignal, createMemo, splitProps, useContext, type JSX, type Accessor } from "solid-js";
import { useTheme } from "@ares/shared/solid";

const SIDEBAR_WIDTH = 28;
const SIDEBAR_WIDTH_ICON = 6;

type BoxProps = JSX.IntrinsicElements["box"];
type OpenState = boolean | ((prev: boolean) => boolean);

type SidebarContextProps = {
    open: Accessor<boolean>;
    setOpen: (open: OpenState) => void;
    toggleSidebar: () => void;
};

type SidebarProviderProps = BoxProps & {
    defaultOpen?: boolean;
    open?: boolean;
    onOpenChange?: (open: OpenState) => void;
};

type SidebarProps = BoxProps & {
    side?: "left" | "right";
    collapsible?: "icon" | "none";
};

type SidebarMenuButtonProps = BoxProps & {
    isActive?: boolean;
    onClick: () => void;
};

function composeClickHandlers(...handlers: Array<BoxProps["on:click"] | undefined>): BoxProps["on:click"] {
    return (event) => {
        for (const handler of handlers) {
            handler?.(event);
        }
    };
}

const SidebarContext = createContext<SidebarContextProps | null>(null);

function useSidebar() {
    const context = useContext(SidebarContext);
    if (!context) {
        throw new Error("useSidebar must be used within a SidebarProvider.");
    }
    return context;
}

function SidebarProvider(props: SidebarProviderProps) {
    const [local, boxProps] = splitProps(props, ["defaultOpen", "open", "onOpenChange", "children"]);
    const [_open, _setOpen] = createSignal(local.defaultOpen ?? true);

    const open = () => local.open !== undefined ? local.open : _open();

    const setOpen = (value: OpenState) => {
        if (local.onOpenChange) {
            local.onOpenChange(value);
        } else {
            _setOpen(value);
        }
    };

    const toggleSidebar = () => setOpen((prev) => !prev);


    const contextValue: SidebarContextProps = {
        open,
        setOpen,
        toggleSidebar,
    };

    const theme = useTheme();

    return (
        <SidebarContext.Provider value={contextValue}>
            <box
                {...boxProps}
                bg={boxProps.bg ?? theme()?.bg ?? "#1e1e2e"}
                fg={boxProps.fg ?? theme()?.fg ?? "#cdd6f4"}
                flexDirection={boxProps.flexDirection ?? "row"}
                flexGrow={boxProps.flexGrow ?? 1}
                width={boxProps.width ?? { percent: 100 }}
                height={boxProps.height ?? { percent: 100 }}
            >
                {local.children}
            </box>
        </SidebarContext.Provider>
    );
}

function Sidebar(props: SidebarProps) {
    const [local, boxProps] = splitProps(props, ["side", "collapsible", "children"]);
    const { open } = useSidebar();
    const theme = useTheme();

    const collapsible = () => local.collapsible ?? "icon";
    const width = () => {
        if (collapsible() === "none") return SIDEBAR_WIDTH;
        return open() ? SIDEBAR_WIDTH : SIDEBAR_WIDTH_ICON;
    };

    return (
        <box
            {...boxProps}
            bg={boxProps.bg ?? theme()?.sidebar ?? "#1e1e2e"}
            fg={boxProps.fg ?? theme()?.sidebarFg ?? "#cdd6f4"}
            flexDirection={boxProps.flexDirection ?? "column"}
            width={boxProps.width ?? { point: width() }}
            height={boxProps.height ?? { percent: 100 }}
            display={boxProps.display ?? (open() ? "flex" : "none")}
        >
            {local.children}
        </box>
    );
}

function SidebarTrigger(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children", "on:click"]);
    const { toggleSidebar } = useSidebar();
    const theme = useTheme();

    return (
        <box
            {...boxProps}
            on:click={composeClickHandlers(local["on:click"], () => toggleSidebar())}
            bg={boxProps.bg ?? theme()?.sidebarAccent ?? "#313244"}
            fg={boxProps.fg ?? theme()?.sidebarAccentFg ?? "#cdd6f4"}
            width={boxProps.width ?? { point: 3 }}
        >
            {local.children ?? "☰"}
        </box>
    );
}

function SidebarInset(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    const theme = useTheme();

    return (
        <box
            {...boxProps}
            bg={boxProps.bg ?? theme()?.mutedBg ?? "#181825"}
            fg={boxProps.fg ?? theme()?.fg ?? "#cdd6f4"}
            flexDirection={boxProps.flexDirection ?? "column"}
            flexGrow={boxProps.flexGrow ?? 1}
        >
            {local.children}
        </box>
    );
}

function SidebarHeader(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            padding={boxProps.padding ?? { all: { point: 1 } }}
        >
            {local.children}
        </box>
    );
}

function SidebarFooter(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            padding={boxProps.padding ?? { all: { point: 1 } }}
        >
            {local.children}
        </box>
    );
}

function SidebarContent(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            flexGrow={boxProps.flexGrow ?? 1}
            overflow={boxProps.overflow ?? "scroll"}
        >
            {local.children}
        </box>
    );
}

function SidebarGroup(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            width={boxProps.width ?? { percent: 100 }}
        >
            {local.children}
        </box>
    );
}

function SidebarGroupLabel(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    const { open } = useSidebar();

    return (
        <box
            {...boxProps}
            height={boxProps.height ?? { point: 1 }}
            padding={boxProps.padding ?? { horizontal: { point: 1 } }}
            display={boxProps.display ?? (open() ? "flex" : "none")}
        >
            {local.children}
        </box>
    );
}

function SidebarGroupAction(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    const { open } = useSidebar();

    return (
        <box {...boxProps} display={boxProps.display ?? (open() ? "flex" : "none")}>
            {local.children}
        </box>
    );
}

function SidebarGroupContent(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            width={boxProps.width ?? { percent: 100 }}
        >
            {local.children}
        </box>
    );
}

function SidebarMenu(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            width={boxProps.width ?? { percent: 100 }}
        >
            {local.children}
        </box>
    );
}

function SidebarMenuItem(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "row"}
            width={boxProps.width ?? { percent: 100 }}
        >
            {local.children}
        </box>
    );
}

function SidebarMenuButton(props: SidebarMenuButtonProps) {
    const [local, boxProps] = splitProps(props, ["isActive", "children", "onClick", "on:click"]);
    return (
        <box
            {...boxProps}
            on:click={composeClickHandlers(local["on:click"], () => local.onClick())}
            flexDirection={boxProps.flexDirection ?? "row"}
            width={boxProps.width ?? { percent: 100 }}
            height={boxProps.height ?? { point: 1 }}
            padding={boxProps.padding ?? { horizontal: { point: 1 } }}
        >
            {local.children}
        </box>
    );
}

function SidebarMenuAction(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    const { open } = useSidebar();

    return (
        <box {...boxProps} display={boxProps.display ?? (open() ? "flex" : "none")}>
            {local.children}
        </box>
    );
}

function SidebarMenuBadge(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    const { open } = useSidebar();

    return (
        <box {...boxProps} display={boxProps.display ?? (open() ? "flex" : "none")}>
            {local.children}
        </box>
    );
}

function SidebarMenuSub(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    const { open } = useSidebar();

    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "column"}
            padding={boxProps.padding ?? { left: { point: 1 } }}
            display={boxProps.display ?? (open() ? "flex" : "none")}
        >
            {local.children}
        </box>
    );
}

function SidebarMenuSubItem(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box {...boxProps} flexDirection={boxProps.flexDirection ?? "row"}>
            {local.children}
        </box>
    );
}

function SidebarMenuSubButton(props: BoxProps & { isActive?: boolean }) {
    const [local, boxProps] = splitProps(props, ["isActive", "children"]);
    return (
        <box
            {...boxProps}
            flexDirection={boxProps.flexDirection ?? "row"}
            height={boxProps.height ?? { point: 1 }}
            padding={boxProps.padding ?? { horizontal: { point: 1 } }}
        >
            {local.children}
        </box>
    );
}

function SidebarSeparator(props: BoxProps) {
    const [local, boxProps] = splitProps(props, ["children"]);
    return (
        <box
            {...boxProps}
            height={boxProps.height ?? { point: 1 }}
            width={boxProps.width ?? { percent: 100 }}
            margin={boxProps.margin ?? { horizontal: { point: 1 } }}
        >
            {local.children ?? "─".repeat(40)}
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
