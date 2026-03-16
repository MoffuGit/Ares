i get this error:
[1] Uncaught exception in worker: 5294 |   }
[1] 5295 |   start() {
[1] 5296 |     this.core.on("SettingsUpdate", this.onSettingsUpdate);
[1] 5297 |     this.core.on("ThemeUpdate", this.onThemeUpdate);
[1] 5298 |     this.core.on("FiletreeUpdate", this.onFiletreeUpdate);
[1] 5299 |     console.log("start: keymaps count=", keymaps.length, JSON.stringify(keymaps.slice(0, 3)));
[1]                                                                               ^
[1] TypeError: JSON.stringify cannot serialize BigInt.
[1]       at start (/Volumes/Home_SSD/Users/home/Documents/projects/Ares/packages/app/desktop/build/dev-macos-arm64/react-tailwind-vite-dev.app/Contents/Resources/app/bun/index.js:5299:72)
[1]       at /Volumes/Home_SSD/Users/home/Documents/projects/Ares/packages/app/desktop/build/dev-macos-arm64/react-tailwind-vite-dev.app/Contents/Resources/app/bun/index.js:5470:11

and second, the keymaps on the ts side should be stored by scope and mode, right now
they all get inserted to the same array, i need them to be separated, that way i can access to the ones that the components cares about
