import { useAppStore } from "@/lib/app";

export function BottomBar() {
    const mode = useAppStore((state) => state.mode);

    return (
        <div className="h-7 border-t border-t-background flex align-middle justify-start">
        </div>
    )
}
