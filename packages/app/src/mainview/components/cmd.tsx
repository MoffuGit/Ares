import { Command, CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "./ui/command";
import { useAppStore } from "@/lib/app";

export function Cmd() {
    const { cmdOpen, setCmdOpen } = useAppStore();

    return (
        <CommandDialog open={cmdOpen} onOpenChange={setCmdOpen}>
            <Command>
                <CommandInput placeholder="Type a command or search..." />
                <CommandList>
                    <CommandEmpty>No results found.</CommandEmpty>
                    <CommandGroup heading="Suggestions">
                        <CommandItem>Calendar</CommandItem>
                        <CommandItem>Search Emoji</CommandItem>
                        <CommandItem>Calculator</CommandItem>
                    </CommandGroup>
                </CommandList>
            </Command>
        </CommandDialog>
    )
}
