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
        <div className="h-auto w-full flex flex-wrap items-center align-middle gap-1 text-xs wrap-break-word text-muted-foreground px-1">
            <Button
                size="icon-xs"
                variant="ghost"
                className="hover:bg-accent/60 data-[active=true]:bg-accent/60 dark:data-[active=true]:bg-accent"
                onClick={() => toggleSidebarKind("filetree")}
                data-active={sidebarOpen && sidebarView === "filetree"}
            >
                <FolderTree />
            </Button>
            {tabsInSidebar ? (
                <Button
                    size="icon-xs"
                    variant="ghost"
                    className="hover:bg-accent/60 data-[active=true]:bg-accent/60 dark:data-[active=true]:bg-accent"
                    onClick={() => toggleSidebarKind("tabs")}
                    data-active={sidebarOpen && sidebarView === "tabs"}
                >
                    <ListTree />
                </Button>
            ) : null}
            <Separator orientation="vertical" className="my-1" />
            <div className="ml-auto font-geist-mono font-normal text-xs text-muted-foreground/80 leading-none uppercase mt-0.5">
                {mode}
            </div>
        </div>
    )
}
