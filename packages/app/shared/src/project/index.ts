import type { CoreLib } from "@ares/core";
import type { Pointer } from "bun:ffi";
import { basename } from "node:path";
import type { WorktreeEntry } from "../types";

export class Project {
    protected coreProject: Pointer;
    coreLib: CoreLib;
    abs_path: string;
    root: string;

    constructor(core: CoreLib, app: Pointer, abs_path: string) {
        const coreProject = core.createProject(app, abs_path);
        if (coreProject == null) throw new Error("Failed to create project")

        this.coreLib = core;
        this.abs_path = abs_path;
        this.coreProject = coreProject;
        this.root = basename(abs_path);
    }

    readFiletree() {
        const raw = this.coreLib.readFileTree(this.coreProject);
        const entries: WorktreeEntry[] = raw.map((e) => {
            const path = e.path ?? "";
            const parts = path.split("/");
            return {
                id: Number(e.id),
                name: parts[parts.length - 1] ?? path,
                path,
                kind: e.kind === 1 ? "dir" : "file",
                fileType: e.file_type ?? "unknown",
                expanded: e.is_expanded,
                depth: e.depth,
            };
        });
        return entries;
    }

    expandEntry(id: number) {
        this.coreLib.expandEntry(this.coreProject, id);
    }

    destroy() {
        this.coreLib.destroyProject(this.coreProject);
    }
}
