import { WorktreeEntry } from "@ares/shared";
import { useTheme } from "@ares/shared/react";
import { File, Folder } from "lucide-react";

export function FileIcon({ entry }: { entry: WorktreeEntry }) {
    const theme = useTheme()

    const color = theme?.fileType[entry.fileType] ?? theme?.fg

    return (
        <div className="size-3 flex items-center align-middle [&_svg:not([class*='size-'])]:size-3" style={{ color }}>
            {
                entry.kind == "dir" ? <Folder /> : <File />
            }
        </div>
    )
}
