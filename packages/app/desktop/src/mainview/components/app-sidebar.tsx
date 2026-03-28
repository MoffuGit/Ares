import {
    Sidebar,
    SidebarRail,
} from "@/components/ui/sidebar"
import { FileTree } from "./file-tree"
import { SidebarTabs } from "./sidebar-tabs"
import { useAppStore } from "@/lib/app"

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
    const sidebarView = useAppStore((state) => state.sidebarView)

    return (
        <Sidebar {...props}>
            {sidebarView === "tabs" ? <SidebarTabs /> : <FileTree />}
            <SidebarRail />
        </Sidebar>
    )
}
