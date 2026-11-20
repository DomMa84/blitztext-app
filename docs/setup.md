# Setup

## 1. Install

Either download the signed app from the [releases page](https://github.com/cmagnussen/blitztext-app/releases/latest), or build it:

```bash
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain   # once; the local language model (MLX) needs it
git clone https://github.com/cmagnussen/blitztext-app.git
cd blitztext-app
./build.sh --install --run
```

The app is installed to `/Applications/Blitztext.app` and appears in the menu bar.

### Installer (DMG) without Xcode

The workflow `.github/workflows/dmg.yml` builds `Blitztext-<version>.dmg` on GitHub's Macs, so a Mac with little free space does not need Xcode:

- **Every push to `main`**, or **Actions > DMG > Run workflow**: open the run and download **Blitztext-DMG** under Artifacts (a ZIP that holds the DMG; you must be signed in to GitHub).
- **A tag** such as `v1.18.1-1`: the DMG is also attached to a release of that name.

To build the DMG on your own Mac instead: `./build.sh --dmg` writes it to `dist/` (`python3 -m pip install dmgbuild` gives it the window layout).

Open the DMG and drag **Blitztext** onto **Programme**. Any other folder works too, for example on an external SSD; that drive must then be connected whenever Blitztext starts.

These builds are signed ad hoc, not notarized by Apple. The first time you open one, macOS says it could not check the app. Click **Fertig**, open **System Settings > Privacy & Security**, click **Open Anyway** next to Blitztext and confirm. Every new build also needs **Accessibility** again: in Blitztext under Allgemein, click "Freigabe zurücksetzen".

## 2. Permissions

- **Microphone:** to record.
- **Accessibility:** to paste into the app you are using. Without it, results stay on the clipboard.

If paste stops working after an update or rebuild, open **System Settings > Privacy & Security > Accessibility**, remove old Blitztext entries, add the current app and restart Blitztext.

## 3. Local Speech Model

Open **Settings > Modelle > Spracherkennung**, pick a model and load it once:

- **Parakeet Ultra** (recommended on Apple silicon): fast, 25 European languages, about 630 MB.
- **Whisper Large v3 Turbo / Small:** about 100 languages, slower.

After a macOS update the first dictation can take a few minutes while macOS prepares the model for the Neural Engine. Blitztext shows a hint; keep it running.

## 4. Writing Modes

Blitztext+, $%&! and :) need a language model:

- **Apple Intelligence** (macOS 26, turned on in System Settings): runs on your Mac. Nothing to configure.
- **Your own model provider** (optional): **Settings > Modelle > Modell-Anbieter**, choose a provider, paste your API key, test the connection. Local servers such as Ollama or LM Studio work via "Eigene Adresse".

## 5. Shortcuts

`fn` shortcuts only work on Apple keyboards. For other keyboards set your own shortcut per mode in **Settings > Allgemein > Tastenkürzel** (e.g. `⌃⌥D` or `F13`). An own shortcut replaces the `fn` shortcut of that mode. `fn` itself cannot be part of an own shortcut.

**Halten:** hold to record, release to process. **Drücken:** press to start, press again or `Esc` to stop.

## 6. Changes From The Original (Fork)

This fork does not take over the original's changes by itself. Every Monday `.github/workflows/upstream-check.yml` compares it with [cmagnussen/blitztext-app](https://github.com/cmagnussen/blitztext-app); when something is new there, it opens an issue **Neu im Original** (label `upstream`) with one checkbox per change, its description and the new versions. Tick what you want and take those changes over one by one as pull requests. **Actions > Upstream check > Run workflow** checks right away; `python3 scripts/upstream-check.py --dry-run` prints the list locally.

The next issue lists only what came after the last one, and changes already taken over (cherry-picked) are left out. Issues must be on for the fork: **Settings > General > Features > Issues**.
