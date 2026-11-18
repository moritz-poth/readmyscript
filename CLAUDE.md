# Read my Script

macOS app (public on GitHub as `moritz-poth/readmyscript`, GPL-3.0-or-later): screenplay PDF → audiobook (.m4b, one chapter per scene) through the local VoiceStudio app. A narrator reads the action; every role has its own voice. Plan and early decisions: `docs/plan.md` (it started as a private tool; since 2026-11-18 it has the full set of the other apps: updater, settings window, self-test, manual, four languages).

## Legal rule: the script never leaves the computer
- Network peers: VoiceStudio on `http://127.0.0.1:3900` (scripts) and, for updates only, `api.github.com/repos/moritz-poth/readmyscript/releases` + the release assets (user decision 2026-11-18). `PlannerTests.testOnlyKnownAddressesInSources` fails on any other URL in `Sources/` (browser links: repo, GPL page, coffee). Nothing from a script ever goes to GitHub.
- Support has **no sending** (user decision 2026-11-18): self-test results stay on screen, "Show log file" only. No Cloudflare worker, no problem form – the log holds PDF file names (script titles).
- The app warns when VoiceStudio's usage statistics (`analytics_enabled` in `~/Library/Application Support/OmniVoice/prefs.json`) or its cloud sync (`/api/cloud-sync/status`) are on.
- The log holds events and file names only, never script text.
- **For Claude:** ask the user before touching any real script PDF – even file names are content (titles leaked once). Never print real script text, role names or scene headings into the conversation. Check real scripts with `rms-dump <pdf> --stats` (numbers and letter shapes only), and only after a successful build (`swift build --product rms-dump && …`): a failed build once ran an old binary that printed a whole script. Real scripts stay outside the repo (`.gitignore` drops *.pdf/*.m4b).

## Layout
- `Sources/ScriptCore` – `PDFLines` (PDFKit line selections with position, font size, grey), `ScriptParser` (noise filter → learned columns → element kinds), `Cast`/`RenderPlan` (what VoiceStudio renders), `VoiceStudio` (health, profiles, `/generate` preview, design profiles, `/longform/render` SSE, collect output), `VoiceDesign`, `FakeScript` (draws synthetic screenplay PDFs: Final Draft and Word/A4 layouts, header, page/scene numbers, diagonal grey watermark, (MORE)/(CONT'D)), `DemoScript` (the self-test's invented script). No UI.
- `Sources/ReadMyScript` – SwiftUI app: `AppModel`, `Views` (drop zone, cast panel, design sheet, script preview with right-click "Read by narrator"/"Don't read"), `Settings` (AppSettings: dark, language, test versions), `SettingsWindow` (Mountpoint-style tab window 800×450: General, Updates, Support, About + `AboutView`), `Updater` (Mountpoint's, with `UpdateBanner`), `SelfTest`, `Manual` (MarkTheRoughcut's renderer), `Theme`.
- `Sources/rms-dump` – `rms-dump <pdf>` (elements), `--lines` (raw lines), `--stats` (numbers only), `--render <out.m4b>` (end-to-end with VoiceStudio, first voice narrates; roles beyond the number of voices are not read).

## Cast rules
- One voice per part: `Cast.suggest` gives each voice at most once (narrator first, then roles by lines); leftovers stay unassigned (`roles[name] == nil`, UI "Choose Voice"). `.some(nil)` = "Don't read" (a decision). Unassigned roles block "Create Audiobook…". Picking a voice someone else uses asks first (`confirmShare`, NSAlert).

## Parser rules worth knowing
- Noise: light grey (>0.55 white), line height > 2.5× median (rotated), font size off by ×1.6, same text (digits masked) at the same height on ≥30 % of pages, page/scene numbers, (MORE)/(WEITER).
- Columns come from "upper-case line followed by a less-indented line" pairs (cue → dialogue). Without them: no-indent mode (upper-case name, then text; also "NAME: text").
- Everything before the first scene heading (title page, FADE IN) is dropped. Not spoken: scene headings (chapter titles), cues, parentheticals (also inline "(lacht) …" and mid-line), transitions.
- Upper-case words of 4+ letters in spoken text become capitalised (character introductions); shorter ones stay (acronyms).

## VoiceStudio facts (0.5.8)
- `POST /longform/render` {chapters:[{title, spans:[{voice_id=profile id, text, pause_ms_after}]}], language "German"/"English"/null, format m4b} → SSE `started/progress/chapter/chapter_error/assembling/done{output}/error`. Disconnecting stops it; finished segments are cached (`outputs/longform_cache`), so Pause = disconnect, Resume = same plan again.
- Output lands in `~/Library/Application Support/OmniVoice/outputs/story_<job>.m4b` + work folder `story_<job>/`; `collect` moves the file and deletes the folder.
- New voices: `POST /profiles` multipart `kind=design`, `instruct` ("female, elderly, low pitch[, whisper]"), `vd_states` (JSON, required), `seed`, `language` → profile usable in longform. Same `instruct`+`seed` on `/generate` = unsaved preview. Tags: `ScriptCore/VoiceDesign.swift`.
- Speed: ~7× real time on Apple Silicon (66 s audio took 468 s).
- Cloned voices may put a junk word in front of a line ("Los, …") – comes from the voice's reference clip; fix the clip in VoiceStudio.

## Settings, updates, languages
- Settings window like Mountpoint's (`SettingsWindow.shared.show(pane)`; App menu "About Read my Script" → About tab, "Settings…" ⌘, → last other tab). Help menu: Manual (`Resources/help/<code>.md`, ⌘?) and Show Log File.
- Languages en (keys, default – not the system language), de, fr, es. All translations live in `scripts/strings.py` (run it to regenerate the three `Localizable.strings`); `LocalizationTests` checks every UI string in all three and the manual in all four. Switching the language restarts the app (AppleLanguages, like MarkTheRoughcut) – blocked while an audiobook is rendering or paused (`AppModel.working`).
- Updater = Mountpoint's: releases API, asset `ReadMyScript-<release>.zip` + `.sig` (Ed25519, `scripts/update-key.swift`, Keychain service "Read my Script update key", public key in `Updater.publicKey` – never replace it), tag `v<release>`, Info.plist `ReadMyScriptRelease` must equal the tag, codesign verify, old app to Trash, relaunch. No install while `working`. Test versions = GitHub prereleases (setting "Get test versions").
- Self-test (Settings → Support): demo PDFs → parser, plan, VoiceStudio health/voices/one test sentence, analytics + cloud sync off. Sends nothing.

## Build / test
`swift test` (swift-testing; no Xcode here), `scripts/build-app.sh` → `dist/Read my Script.app` + `dist/ReadMyScript-<release>.zip` + `.sig` (universal, ad-hoc, hardened runtime; prints "NOT SIGNED" without the Keychain key). Release: bump VERSION/RELEASE/BUILD, prerelease first, user installs via the updater, "auf latest" only on the user's word. App icon: `Resources/icon/AppIcon.svg` (variant A2: cassette teal, reels yellow, back page red, white page, grey foot; 1024 grid) → `AppIcon.icns` via `render_png.py` + `iconutil`; rebuild the .icns by hand when the SVG changes; `assets/icon.png` for the README. Commit identity `moritz-poth <mail@moritz-poth.com>` (local git config). Open: README/manual screenshots from neutral demo material.
