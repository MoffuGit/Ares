import { useAppStore } from "@/lib/app";

export function BottomBar() {
    const mode = useAppStore((state) => state.mode);

    return (
        <div className="h-7 w-full flex flex-wrap items-center gap-1 text-xs wrap-break-word text-muted-foreground px-2">
            <span
                className="h-3.5 w-1 rounded-full opacity-80"
                style={{
                    backgroundColor:
                        mode === "normal"
                            ? "var(--mode-normal)"
                            : mode === "visual"
                              ? "var(--mode-visual)"
                              : "var(--mode-insert)",
                }}
            />
        </div>
    )
}
