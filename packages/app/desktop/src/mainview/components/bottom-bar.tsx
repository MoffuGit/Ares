import { useAppStore } from "@/lib/app";

export function BottomBar() {
    const mode = useAppStore((state) => state.mode);

    return (
        <div className="h-7 w-full flex flex-wrap items-center gap-1 text-xs wrap-break-word text-muted-foreground px-2">
            <span className="h-3.5 w-1 rounded-full data-[mode=normal]:bg-red-500/40 data-[mode=visual]:bg-blue-500/40 data-[mode=insert]:bg-purple-500/40" data-mode={mode} />
        </div>
    )
}
