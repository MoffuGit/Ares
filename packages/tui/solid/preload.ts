import { plugin } from "bun";
import { transformSync } from "@babel/core";

plugin({
    name: "solid-jsx",
    setup(build) {
        build.onLoad({ filter: /\.[jt]sx$/ }, async ({ path }) => {
            const source = await Bun.file(path).text();
            const result = transformSync(source, {
                filename: path,
                presets: [
                    ["@babel/preset-typescript", { isTSX: true, allExtensions: true }],
                    ["babel-preset-solid", { generate: "universal", moduleName: "@ares/tui-solid" }],
                ],
            });
            return { contents: result?.code ?? "", loader: "js" };
        });
    },
});
