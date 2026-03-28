import {
    Sidebar,
    SidebarRail,
} from "@/components/ui/sidebar"
import { FileTree } from "./file-tree"
import { SidebarTabs } from "./sidebar-tabs"
import { useAppStore } from "@/lib/app"

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
    const kind = useAppStore((state) => state.sidebarKind)

    return (
        <Sidebar {...props}>
            {kind === "tabs" ? <SidebarTabs /> : <FileTree />}
            <SidebarRail />
        </Sidebar>
    )
}
