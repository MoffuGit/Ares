import type { ElectrobunConfig } from "electrobun";

export default {
    app: {
        name: "react-tailwind-vite",
        identifier: "reacttailwindvite.electrobun.dev",
        version: "0.0.1",
    },
    build: {
        // Vite builds to dist/, we copy from there
        copy: {
            "dist/index.html": "views/mainview/index.html",
            "dist/assets": "views/mainview/assets",
            "../../../zig-out/lib/libcore.dylib": "lib/libcore.dylib",
        },
        mac: {
            bundleCEF: true,
        },
        linux: {
            bundleCEF: true,
        },
        win: {
            bundleCEF: true,
        },
    },
} satisfies ElectrobunConfig;
