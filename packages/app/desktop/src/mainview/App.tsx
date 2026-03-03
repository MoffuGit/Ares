import { useWorktree } from "@ares/shared/react";
import type { WorktreeEntry } from "@ares/shared";

function FileIcon({ entry }: { entry: WorktreeEntry }) {
    if (entry.kind === "dir") return <span>📁</span>;
    return <span>📄</span>;
}

function WorktreeView() {
    const entries = useWorktree();

    if (entries.length === 0) {
        return <p className="text-sm text-gray-500 p-4">Loading worktree...</p>;
    }

    return (
        <div className="flex flex-col font-mono text-sm overflow-auto h-full">
            {entries.map((entry) => (
                <div
                    key={entry.id}
                    className="flex items-center gap-1.5 px-2 py-0.5 hover:bg-white/5 cursor-pointer"
                    style={{ paddingLeft: `${entry.depth * 16 + 8}px` }}
                >
                    <FileIcon entry={entry} />
                    <span>{entry.name}</span>
                </div>
            ))}
        </div>
    );
}

function App() {
    return (
        <div className="flex h-screen">
            <aside className="w-64 border-r border-white/10 overflow-auto">
                <div className="px-3 py-2 text-xs font-semibold uppercase tracking-wider text-gray-500">
                    Explorer
                </div>
                <WorktreeView />
            </aside>
            <main className="flex-1 flex items-center justify-center">
                <p className="text-sm text-gray-500">Select a file to open</p>
            </main>
        </div>
    );
}

export default App;
