import {
    Sidebar,
    SidebarContent,
    SidebarRail,
} from "@/components/ui/sidebar"
import { FileTree } from "./file-tree"

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
    return (
        <Sidebar {...props}>
            <SidebarContent>
                <FileTree />
            </SidebarContent>
            <SidebarRail />
        </Sidebar>
    )
}
