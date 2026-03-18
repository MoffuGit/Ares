import {
    Sidebar,
    SidebarRail,
} from "@/components/ui/sidebar"
import { FileTree } from "./file-tree"

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
    return (
        <Sidebar {...props}>
            <FileTree />
            <SidebarRail />
        </Sidebar>
    )
}
