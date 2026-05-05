import { useEffect, useRef } from "react";
import { useShallow } from "zustand/react/shallow";
import { Command, CommandDialog, CommandGroup, CommandInput, CommandItem, CommandList, CommandShortcut } from "./ui/command";
import { findCmdSequence, selectAvailableCmds, useAppStore } from "@/lib/app";
import { cmdEventEmitter } from "@/lib";
import { MOD_ICONS } from "./mods-icons";

const COMMAND_PALETTE_KEYS: Record<string, string> = {
    up: "ArrowUp",
    down: "ArrowDown",
    select: "Enter",
};


function KeySequence({ sequence }: { sequence: string }) {
    const presses = sequence.trim().split(/\s+/).filter(Boolean);
    return (
        <CommandShortcut>
            <span className="ml-auto inline-flex items-center gap-1 text-xs tracking-widest text-muted-foreground leading-0">
                {presses.map((press, i) => {
                    const parts = press.split("+");
                    const key = parts.pop() ?? "";
                    const mods = parts;
                    return (
                        <span key={i} className="inline-flex items-center gap-1 [&_svg:not([class*='size-'])]:size-3 [&_svg]:shrink-0  group-data-selected/command-item:bg-accent/0 dark:group-data-selected/command-item:bg-accent/0  bg-accent/10 dark:bg-accent/40 rounded-md h-5 px-1">
                            {mods.map((mod) => {
                                const Icon = MOD_ICONS[mod.toLowerCase()];
                                return Icon ? (
                                    <Icon key={mod} />
                                ) : (
                                    <span key={mod}>{mod}</span>
                                );
                            })}
                            <span className="uppercase">{key}</span>
                        </span>
                    );
                })}
            </span>
        </CommandShortcut>
    );
}

export function Cmd() {
    const cmdOpen = useAppStore((s) => s.cmdOpen);
    const setCmdOpen = useAppStore((s) => s.setCmdOpen);
    const mode = useAppStore((s) => s.mode);
    const keymaps = useAppStore((s) => s.settings?.keymaps);
    const cmds = useAppStore(useShallow(selectAvailableCmds));
    const inputRef = useRef<HTMLInputElement>(null);

    useEffect(() => {
        if (!cmdOpen) return;
        const off = cmdEventEmitter.on(
            "command_palette",
            (event) => {
                if (event.cmd.key == "close") {
                    setCmdOpen(false);
                    return;
                }
                const input = inputRef.current;
                if (!input) return;
                const key = COMMAND_PALETTE_KEYS[event.cmd.key];
                if (!key) return;
                input.dispatchEvent(
                    new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
                );
            },
        );
        return off;
    }, [cmdOpen]);

    return (
        <CommandDialog open={cmdOpen} onOpenChange={setCmdOpen}>
            <Command loop>
                <CommandInput ref={inputRef} placeholder="Type a command" />
                <CommandList>
                    <CommandGroup>
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
                                    <span className="text-xs leading-0 text-muted-foreground">
                                        {cmd.scope}
                                    </span>
                                    {sequence && <KeySequence sequence={sequence} />}
                                </CommandItem>
                            );
                        })}
                    </CommandGroup>
                </CommandList>
            </Command>
        </CommandDialog>
    )
}
