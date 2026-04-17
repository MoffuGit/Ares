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
        <div className="h-auto w-full flex flex-wrap items-center align-middle gap-1 text-xs wrap-break-word text-muted-foreground">
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
            <div className="ml-auto font-geist-mono font-normal text-xs text-muted-foreground/80 leading-none uppercase mt-0.5">
                {mode}
            </div>
            <span
                data-mode={mode}
                className="w-3 h-2.5 rounded-full bg-radial-[at_75%_75%] from-5% to-80% data-[mode=normal]:from-mode-normal data-[mode=normal]:to-mode-normal/20 data-[mode=visual]:from-mode-visual data-[mode=visual]:to-mode-visual/20 data-[mode=insert]:from-mode-insert data-[mode=insert]:to-mode-insert/20  mx-1"
            />
        </div>
    )
}
