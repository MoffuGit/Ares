import { useAppStore } from "@/lib/app";
import { FolderTree, ListTree } from "lucide-react";
import { Button } from "../ui/button";
import { Separator } from "../ui/separator";

export function BottomBar() {
    const mode = useAppStore((state) => state.mode);
    const settings = useAppStore((state) => state.settings);
    const sidebarOpen = useAppStore((state) => state.sidebarOpen);
    const sidebarView = useAppStore((state) => state.sidebarKind);
    const toggleSidebarKind = useAppStore((state) => state.toggleSidebarKind);

    const tabsInSidebar = settings?.tabs_position === "vertical";

    return (
        <div className="h-6 w-full flex flex-wrap items-center gap-1.5 text-xs wrap-break-word text-muted-foreground pl-0.5 pr-1.5">
            <Button
                size="icon-xs"
                variant={sidebarOpen && sidebarView === "filetree" ? "secondary" : "ghost"}
                className="gap-1 hover:bg-accent/40"
                onClick={() => toggleSidebarKind("filetree")}
            >
                <FolderTree />
            </Button>
            {tabsInSidebar ? (
                <Button
                    size="icon-xs"
                    variant={sidebarOpen && sidebarView === "tabs" ? "secondary" : "ghost"}
                    className="hover:bg-accent/40"
                    onClick={() => toggleSidebarKind("tabs")}
                >
                    <ListTree />
                </Button>
            ) : null}
            <Separator orientation="vertical" className="my-1" />
            <span
                className="h-3.5 outline-2 outline-background w-1 rounded-full opacity-60 ml-auto mr-0"
                style={{
                    backgroundColor:
                        mode === "normal"
                            ? "var(--mode-normal)"
                            : mode === "visual"
                                ? "var(--mode-visual)"
                                : "var(--mode-insert)",
                }}
            />
        </div>
    )
}
