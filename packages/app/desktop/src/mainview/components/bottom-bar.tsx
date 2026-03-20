import { useAppStore } from "@/lib/app";

export function BottomBar() {
    const mode = useAppStore((state) => state.mode);

    return (
        <div className="h-6 w-full border-t px-2 flex content-center">
            <div className="text-xs w-4 h-full leading-0 bg-blue-500 uppercase text-muted-foreground">
                {mode}
            </div>
        </div>
    )
}
