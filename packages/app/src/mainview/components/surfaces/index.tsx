import type { Surface as SurfaceData } from "@ares/shared";
import { EditorSurface } from "./editor";

export function Surface({ surface, id, active }: { surface: SurfaceData, id: number, active: boolean }) {
    switch (surface.kind) {
        case "editor":
            return <EditorSurface id={id} surface={surface} active={active} />;
        case "terminal":
            return <div />;
    }
}
