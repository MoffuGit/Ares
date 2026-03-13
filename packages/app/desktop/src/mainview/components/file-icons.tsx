import { WorktreeEntry } from "@ares/shared";
import { File, Folder } from "lucide-react";

export function FileIcon({ item }: { item: WorktreeEntry }) {

    return (
        <div className="size-3 flex items-center align-middle [&_svg:not([class*='size-'])]:size-3">
            {
                item.kind == "dir" ? <Folder /> : <File />
            }
        </div>
    )
}
