import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from '@tanstack/router-plugin/vite'
import path from "path";

export default defineConfig({
    plugins: [
        tanstackRouter({
            target: 'react',
            autoCodeSplitting: true,
            routesDirectory: path.resolve(__dirname, 'src/mainview/routes'),
            generatedRouteTree: path.resolve(__dirname, 'src/mainview/routeTree.gen.ts'),
        }),
        tailwindcss(), react()
    ],
    root: "src/mainview",
    build: {
        outDir: "../../dist",
        emptyOutDir: true,
    },
    resolve: {
        alias: {
            "@": path.resolve(__dirname, "./src/mainview"),
            "@ares/shared/react": path.resolve(__dirname, "../shared/src/react/index.ts"),
            "@ares/shared": path.resolve(__dirname, "../shared/src/index.ts"),
        },
    },
    server: {
        port: 5173,
        strictPort: true,
    },
});
