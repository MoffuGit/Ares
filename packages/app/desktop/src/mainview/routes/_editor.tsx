import { createFileRoute, Outlet } from '@tanstack/react-router'
import { useWorktree } from "@ares/shared/react"
import type { WorktreeEntry } from "@ares/shared"

function FileIcon({ entry }: { entry: WorktreeEntry }) {
    if (entry.kind === "dir") return <span>📁</span>;
    return <span>📄</span>;
}


export const Route = createFileRoute('/_editor')({
    component: () => (
        <div className="h-screen flex flex-col">
            <div className='bg-red-500 w-full h-7 electrobun-webkit-app-region-drag cursor-default'>
            </div>
        </div>
    ),
})
