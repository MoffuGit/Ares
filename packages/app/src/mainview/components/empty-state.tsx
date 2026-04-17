import { useAppStore } from "@/lib/app";
import { Button } from "@/components/ui/button";
import {
    Empty,
    EmptyContent,
    EmptyDescription,
    EmptyHeader,
    EmptyMedia,
    EmptyTitle,
} from "@/components/ui/empty";
import { FolderOpenIcon } from "lucide-react";

export function EmptyState() {
    const openProjectDialog = useAppStore((state) => state.openProjectDialog);

    return (
        <div className="flex h-full w-full flex-1 flex-col gap-1.5 rounded-xl bg-muted shadow-inset">
            <Empty>
                <EmptyHeader>
                    <EmptyMedia variant="icon">
                        <FolderOpenIcon />
                    </EmptyMedia>
                    <EmptyTitle className="font-libertinus text-xl leading-none">No project open</EmptyTitle>
                    <EmptyDescription>
                        You haven't created any projects yet. Get started by creating your first project.
                    </EmptyDescription>
                </EmptyHeader>
                <EmptyContent>
                    <Button size="sm" variant="outline" onClick={() => void openProjectDialog()}>
                        <FolderOpenIcon data-icon="inline-start" />
                        Open folder
                    </Button>
                </EmptyContent>
            </Empty>
        </div>
    );
}
