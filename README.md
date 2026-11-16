# CLIferno

Text shortcuts for macOS: type a trigger (e.g. `;gitnb`) and CLIferno replaces it system-wide.

## Install / update to the latest version

Every push to `main` is tested, built and published by GitHub Actions as the release
[`latest`](../../releases/tag/latest). To install or update:

```bash
bash scripts/install.sh
```

The script downloads `CLIferno.zip` from the `latest` release, verifies its SHA-256 checksum,
signs the app with the local signing identity `Atext Local Development` (set up automatically
the first time), quits a running CLIferno, installs it to `/Applications` (falling back to
`~/Applications`) and launches the app. Because the local signature stays the same, the
Accessibility and Input Monitoring permissions are kept across updates.

For a private repository, run `gh auth login` once beforehand. Options:
`--tag <tag>` (different release), `--dir <folder>` (different install location).

The installed version is shown in the bottom-right corner of the "Manage Snippets" window.

## Usage

- **Triggers** start with `;` and are replaced as soon as you type their last character.
- **Search:** press <kbd>Control</kbd> + <kbd>Option</kbd> + <kbd>Space</kbd> anywhere to
  search your snippets by name, trigger or text and insert one.
- **Placeholders:** `$1`, `$2`, … in a snippet are asked for before inserting. `$$1` inserts
  a literal `$1`; `$$` gives a dollar sign.
- **Import / export** your snippets as JSON from the "Manage Snippets" window.

## Appearance (light / dark)

In the top-right corner of the window, or in the menu bar icon under **Appearance**:
*Match System*, *Light* or *Dark*. The choice is remembered.

## Languages

The app is in English and ships with a German translation. macOS picks the language from
**System Settings → General → Language & Region** (or per app under *Applications*).

To add a language, create `Resources/<code>.lproj/Localizable.strings` (and optionally
`InfoPlist.strings`) using `Resources/de.lproj` as a template, and add the code to
`CFBundleLocalizations` in `Resources/Info.plist`. The keys are the English strings used in
the source code; interpolated values appear as `%@` (text) or `%lld` (numbers).

## Build it yourself

```bash
bash scripts/setup-signing.sh   # once
bash scripts/build-app.sh       # creates dist/CLIferno.app
swift test
```

## Former name "Atext"

The app used to be called Atext. On first launch, CLIferno automatically moves the saved
snippets from `~/Library/Application Support/Atext` to `…/CLIferno`, and the installer removes
an old `Atext.app`. The bundle ID (`dev.local.atext`) and certificate name
(`Atext Local Development`) intentionally stay the same so macOS keeps the Accessibility and
Input Monitoring permissions.
