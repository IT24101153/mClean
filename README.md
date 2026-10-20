# mClean

A minimal, native macOS cleaner built in SwiftUI on top of the open-source
[Mole](https://github.com/tw93/Mole) engine.

| Screen | What it does | Engine command |
| --- | --- | --- |
| Overview | Health score, storage, memory, CPU and battery, live; Empty Trash | `mole status --watch` |
| System Junk | Caches, logs and leftovers from deleted apps; choose what's never cleaned | `mole clean --dry-run`, then `mole clean` |
| Applications | Remove an app and its related files (to the Trash); list shows instantly from a cache | `mole uninstall --list`, `--dry-run`, then real run |
| Disk Space | Drill into folders, find large files, delete items (to the Trash, confirmed twice) | `mole analyze --json <path>` |
| Installers | Leftover `.dmg`, `.pkg`, `.iso`, `.xip` and installer `.zip` files, picked one by one | Native scan following Mole's rules |
| Audio Plugins | AU, VST, VST3, AAX and CLAP plugins grouped per product; uninstall (to the Trash, with settings and optional presets); reset plugin caches; remove unused AAX versions; presets from vendors no longer installed | Native scan |
| Optimize | Refresh caches, rebuild indexes, repair preferences | `mole optimize --dry-run`, then `mole optimize` |
| Developer Junk | `node_modules`, `build`, `.gradle` and similar folders, picked one by one (to the Trash) | `mole purge --dry-run` |
| History | Real cleanups from Mole's log plus mClean's own actions | `mole history --json` |

Every destructive action is previewed first, and the user confirms it before
it runs. A menu bar icon shows free space and offers a quick System Junk scan
and clean, and a notification appears when a long task finishes in the
background. Quitting while a cleanup runs asks first, then stops it the same
way Cancel does. The first launch shows a welcome screen that explains Full
Disk Access.

## Screenshots

<table>
<tr>
<td align="center"><img src="mClean%20SS/1.png" width="380"><br><sub><b>Overview</b></sub></td>
<td align="center"><img src="mClean%20SS/2.png" width="380"><br><sub><b>System Junk</b></sub></td>
<td align="center"><img src="mClean%20SS/3.png" width="380"><br><sub><b>Applications</b></sub></td>
</tr>
<tr>
<td align="center"><img src="mClean%20SS/4.png" width="380"><br><sub><b>Disk Space</b></sub></td>
<td align="center"><img src="mClean%20SS/5.png" width="380"><br><sub><b>Installers</b></sub></td>
<td align="center"><img src="mClean%20SS/6.png" width="380"><br><sub><b>Audio Plugins</b></sub></td>
</tr>
<tr>
<td align="center"><img src="mClean%20SS/7.png" width="380"><br><sub><b>Optimize</b></sub></td>
<td align="center"><img src="mClean%20SS/8.png" width="380"><br><sub><b>Developer Junk</b></sub></td>
<td align="center"><img src="mClean%20SS/9.png" width="380"><br><sub><b>History</b></sub></td>
</tr>
</table>

## Requirements

- macOS 14 or later
- Xcode 26 or later (built and tested with Xcode 27)

## Build

```bash
# 1. Copy one Mole version into Engine/Mole (already done; rerun to update)
Scripts/vendor-mole.sh                      # installed Homebrew release (default)
Scripts/vendor-mole.sh ~/src/Mole           # or a source checkout, built with Go

# 2. Open in Xcode and run, or build from the command line
open mClean.xcodeproj
xcodebuild -project mClean.xcodeproj -scheme mClean -configuration Release build

# 3. Run the parser tests (fast, and they don't launch the app)
xcodebuild -project mClean.xcodeproj -scheme mClean test
```

The app is signed with the Apple Development certificate for team
`U359G8W7UA`. macOS ties privacy grants such as Full Disk Access to that
signature, so they survive rebuilds. A build signed only for this Mac would
lose the grant every time.

`vendor-mole.sh` always takes the shell scripts and the two Go helpers
(`analyze-go`, `status-go`) from the same Mole version, never a mix. From an
installed release such as Homebrew's it copies both. From a source checkout it
builds the helpers with Go. `Engine/Mole/ENGINE_SOURCE` records which version
is bundled (currently Mole 1.59.1 from Homebrew). The "Embed Mole Engine" build
phase (`Scripts/embed-engine.sh`) puts the engine and mClean's helper scripts
in `mClean.app/Contents/Resources` and signs the Go helpers.

## Logo and app icon

`mclean.png` (square artwork, at least 1024 px recommended) is the source for
both the app icon and the in-app logo. After changing it, regenerate the assets:

```bash
swift Scripts/make-icon.swift mclean.png mClean/Assets.xcassets
```

This places the artwork in the standard macOS rounded-square icon shape and
writes `AppIcon.appiconset` and `Logo.imageset`.

## How it works

- `Engine/MoleEngine.swift` runs the bundled `mole` with `Process`, using the
  login shell's `PATH` so Mole can find `brew`, `npm` and other tools. It
  streams output line by line, and cancelling a task sends Ctrl-C to Mole.
- Mole prints plain text when it isn't attached to a terminal.
  `MoleReport.swift` turns the `➤ section` / `✓ item · detail` lines and the
  `=====` summary block into sections, items and totals.
  `MoleTextParsers.swift` reads the clean file list, the uninstall plan and the
  purge candidates.
- Status, app list, disk analysis and history come from Mole's JSON output.
- `MoleJob.swift` is the shared preview → review → run flow used by System
  Junk, Optimize and Developer Junk. Every engine command is tagged as
  monitoring, scanning or changing files. Scans and changes keep the Mac awake,
  and changes make quitting ask first.
- "Never Clean" edits Mole's protection list (`~/.config/mole/whitelist`)
  through `Engine/mclean-protect.sh`, which calls Mole's own functions. Saving
  the list replaces Mole's optional defaults, so the script always writes them
  back along with your choices.
- Audio Plugins reads each plugin's `Info.plist`. Formats of one product are
  grouped by the name stored in the bundle (iZotope's files differ per format;
  the stored name doesn't), and vendors are linked through bundle IDs because
  iZotope's VST3 and AAX copyright lines name its parent company. Apple's
  plugins are hidden and never removed. System-wide plugins are root-owned, so
  `Engine/mclean-admin-trash.sh` moves them to the Trash through macOS's
  administrator prompt. It accepts only paths in the audio plugin and preset
  folders, refuses links and `..`, and gives moved items back to the user.
- Developer Junk, Installers and Disk Space move items to the Trash
  themselves, so mClean keeps its own activity log for History
  (`~/Library/Application Support/mClean/activity.json`).
- `mCleanTests/` checks the parsers against real Mole 1.59.1 output in
  `mCleanTests/Fixtures`, with personal details replaced.
- When Mole needs an administrator password, `sudo` runs `askpass.sh`, which
  shows a native password dialog.
- System Junk cleans user-level items without asking for a password. Mole
  skips system-level caches unless administrator access is already available.

## Permissions

- **Full Disk Access** (optional, in System Settings → Privacy & Security):
  lets mClean empty the Trash and measure protected folders. macOS applies it
  only after the app restarts, so the notice has both an **Open Settings** and
  a **Reopen** button. When access first appears, mClean clears Mole's cached
  disk measurements (`~/.cache/mole/analyzer`) so folders are measured again
  with full access.
- The app is **not sandboxed**. A cleaner has to reach `~/Library` and run the
  engine, so it can't ship on the Mac App Store as-is.

## Debug snapshots

Debug builds can save screenshots of each screen without Screen Recording
permission. Actions only run previews, never deletions:

```bash
open -g -n \
  --env MCLEAN_SNAPSHOT_DIR=/tmp/shots \
  --env MCLEAN_APPEARANCE=light \
  --env MCLEAN_SNAPSHOT_SCRIPT="overview:6,junk-scan:30,apps:15,space:10" \
  build/DerivedData/Build/Products/Debug/mClean.app
```

## License and naming

Mole is licensed under **GPL-3.0**, and this app bundles it. If you distribute
mClean, the distribution must comply with GPL-3.0, which includes making
mClean's source available under the same license.

Mole's [trademark policy](https://github.com/tw93/Mole/blob/main/TRADEMARK.md)
asks forks to use their own name and icon and not to imply endorsement. That's
why this app is called mClean and only credits Mole as its engine.
