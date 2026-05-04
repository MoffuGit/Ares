import { useShallow } from "zustand/react/shallow";
import { Command, CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList, CommandShortcut } from "./ui/command";
import { findCmdSequence, selectAvailableCmds, useAppStore } from "@/lib/app";

export function Cmd() {
    const cmdOpen = useAppStore((s) => s.cmdOpen);
    const setCmdOpen = useAppStore((s) => s.setCmdOpen);
    const mode = useAppStore((s) => s.mode);
    const keymaps = useAppStore((s) => s.settings?.keymaps);
    const cmds = useAppStore(useShallow(selectAvailableCmds));

    return (
        <CommandDialog open={cmdOpen} onOpenChange={setCmdOpen}>
            <Command>
                <CommandInput placeholder="Type a command or search..." />
                <CommandList>
                    <CommandEmpty>No results found.</CommandEmpty>
                    <CommandGroup heading="Commands">
                        {cmds.map(({ cmd, handler }) => {
                            const sequence = findCmdSequence(keymaps, cmd, mode);
                            return (
                                <CommandItem
                                    key={`${cmd.scope}:${cmd.key}`}
                                    value={cmd.title}
                                    onSelect={() => {
                                        setCmdOpen(false);
                                        handler();
                                    }}
                                >
                                    {cmd.title}
                                    {sequence && <CommandShortcut>{sequence}</CommandShortcut>}
                                </CommandItem>
                            );
                        })}
                    </CommandGroup>
                </CommandList>
            </Command>
        </CommandDialog>
    )
}
