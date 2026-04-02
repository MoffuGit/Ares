import type { WorktreeEntry } from "@ares/shared";
import type { ComponentType, SVGProps } from "react";
import { Folder, FolderOpen } from "lucide-react";
import * as Icons from "./ui/icons";
import { useAppStore } from "@/lib/app";

const fileTypeIconMap: Record<string, ComponentType<SVGProps<SVGSVGElement>>> = {
    // Special filenames
    makefile: Icons.Terminal,
    dockerfile: Icons.Docker,
    gitignore: Icons.Git,
    license: Icons.Book,

    // Extensions
    astro: Icons.Astro,
    bun: Icons.Bun,
    c: Icons.C,
    cairo: Icons.Cairo,
    coffee: Icons.Coffeescript,
    cpp: Icons.Cpp,
    cc: Icons.Cpp,
    cxx: Icons.Cpp,
    css: Icons.Css,
    dart: Icons.Dart,
    db: Icons.Database,
    sql: Icons.Database,
    diff: Icons.Diff,
    patch: Icons.Diff,
    elm: Icons.Elm,
    erl: Icons.Erlang,
    hrl: Icons.Erlang,
    ex: Icons.Elixir,
    exs: Icons.Elixir,
    heex: Icons.Phoenix,
    eslintrc: Icons.Eslint,
    fs: Icons.Fsharp,
    fsx: Icons.Fsharp,
    fsi: Icons.Fsharp,
    gleam: Icons.Gleam,
    go: Icons.Go,
    graphql: Icons.Graphql,
    gql: Icons.Graphql,
    h: Icons.C,
    hpp: Icons.Cpp,
    hxx: Icons.Cpp,
    hs: Icons.Haskell,
    lhs: Icons.Haskell,
    hcl: Icons.Hcl,
    tf: Icons.Terraform,
    html: Icons.Html,
    htm: Icons.Html,
    java: Icons.Java,
    js: Icons.Javascript,
    mjs: Icons.Javascript,
    cjs: Icons.Javascript,
    jsx: Icons.React,
    jl: Icons.Julia,
    json: Icons.Code,
    kdl: Icons.Kdl,
    kt: Icons.Kotlin,
    kts: Icons.Kotlin,
    lock: Icons.Lock,
    lua: Icons.Lua,
    luau: Icons.Luau,
    md: Icons.File,
    markdown: Icons.File,
    metal: Icons.Metal,
    nim: Icons.Nim,
    nix: Icons.Nix,
    ipynb: Icons.Notebook,
    ml: Icons.Ocaml,
    mli: Icons.Ocaml,
    php: Icons.Php,
    prisma: Icons.Prisma,
    pp: Icons.Puppet,
    py: Icons.Python,
    r: Icons.R,
    rb: Icons.Ruby,
    rs: Icons.Rust,
    sass: Icons.Sass,
    scss: Icons.Sass,
    scala: Icons.Scala,
    sh: Icons.Terminal,
    bash: Icons.Terminal,
    zsh: Icons.Terminal,
    sql3: Icons.Database,
    sqlite: Icons.Database,
    surql: Icons.Surrealql,
    swift: Icons.Swift,
    tcl: Icons.Tcl,
    toml: Icons.Toml,
    ts: Icons.Typescript,
    mts: Icons.Typescript,
    cts: Icons.Typescript,
    tsx: Icons.React,
    v: Icons.V,
    vue: Icons.Vue,
    vy: Icons.Vyper,
    wgsl: Icons.Wgsl,
    yaml: Icons.Code,
    yml: Icons.Code,
    zig: Icons.Zig,
    zon: Icons.Zig,
    roc: Icons.Roc,

    // Media
    mp3: Icons.Audio,
    wav: Icons.Audio,
    ogg: Icons.Audio,
    flac: Icons.Audio,
    mp4: Icons.Video,
    mov: Icons.Video,
    avi: Icons.Video,
    webm: Icons.Video,
    png: Icons.Image,
    jpg: Icons.Image,
    jpeg: Icons.Image,
    gif: Icons.Image,
    svg: Icons.Image,
    webp: Icons.Image,
    ico: Icons.Image,
    bmp: Icons.Image,

    // Fonts
    ttf: Icons.Font,
    otf: Icons.Font,
    woff: Icons.Font,
    woff2: Icons.Font,

    // Archives
    zip: Icons.Archive,
    tar: Icons.Archive,
    gz: Icons.Archive,
    rar: Icons.Archive,
    "7z": Icons.Archive,
};

export function FileIcon({ entry }: { entry: WorktreeEntry }) {
    const theme = useAppStore((state) => state.theme);

    const color = theme?.fileType[entry.fileType] ?? theme?.fileType["default"] ?? theme?.fg

    const IconComponent = entry.kind === "dir"
        ? (entry.expanded ? FolderOpen : Folder)
        : (fileTypeIconMap[entry.fileType] ?? Icons.File);

    return (
        <div className="size-3.5 flex items-center align-middle [&_svg:not([class*='size-'])]:size-3.5 dark:opacity-50" style={{ color }}>
            <IconComponent />
        </div>
    )
}
