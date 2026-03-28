import { useAppStore } from "@/lib/app";
import { SidebarTrigger } from "./ui/sidebar";
import { Separator } from "./ui/separator";

export function BottomBar() {
    const mode = useAppStore((state) => state.mode);

    return (
        <div className="h-6 w-full flex flex-wrap items-center gap-1.5 text-xs wrap-break-word text-muted-foreground pl-0.5 pr-1.5">
            <SidebarTrigger size="icon-xs" className="hover:bg-accent/40" />
            <Separator orientation="vertical" className="my-1" />
            <span
                className="h-3.5 outline-2 outline-background w-1 rounded-full opacity-60 ml-auto mr-0"
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
