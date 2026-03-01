import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "path";

export default defineConfig({
	plugins: [tailwindcss(), react()],
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
