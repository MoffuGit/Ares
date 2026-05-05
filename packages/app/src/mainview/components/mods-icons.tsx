import { ArrowBigUp, ChevronUp, Command as CommandIcon, Option } from "lucide-react";
import type { ComponentType, SVGProps } from "react";

export const MOD_ICONS: Record<string, ComponentType<SVGProps<SVGSVGElement>>> = {
    shift: ArrowBigUp,
    ctrl: ChevronUp,
    control: ChevronUp,
    alt: Option,
    option: Option,
    super: CommandIcon,
    cmd: CommandIcon,
    meta: CommandIcon,
};
