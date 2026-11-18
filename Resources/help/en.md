# Read my Script

Read my Script turns a screenplay PDF into an audiobook. A narrator reads the action, and every role speaks with its own voice. The voices come from **VoiceStudio**, which runs on the same Mac.

## Your script stays on this Mac

- The script only goes to VoiceStudio on this computer (address 127.0.0.1) – never to the internet.
- The only connection to the internet is the question to GitHub whether there is a new version of Read my Script. It contains nothing from your scripts.
- The log file lists what the app did, without any text from your scripts.
- Read my Script warns you when VoiceStudio's usage statistics or cloud sync are switched on. Switch them off in VoiceStudio before you read a script.

## Before you start

- Install and open **VoiceStudio**. The dot at the top right turns green when it is ready; otherwise click **Start VoiceStudio**.
- Create a few voices in VoiceStudio – or build new ones from Read my Script (see "A new voice").

## Open a script

Drag a screenplay PDF onto the window, or use **File → Open PDF…** (⌘O). Read my Script recognises scene headings, action, character names, parentheticals, dialogue and transitions – in scripts from Final Draft, Fade In, Word and other programs, in German and English. Page numbers, scene numbers, headers and watermarks are left out.

- Everything before the first scene heading (title page, notes) is not read. The cast list tells you how many paragraphs that is.
- PDFs made of scanned pages contain no text and cannot be read yet.

## Cast

The left column lists the **Narrator** and every role, most lines first. Choose a voice for each from its menu, and click ▶ to hear a line of that role in that voice.

- **One voice per role:** Read my Script never gives a voice to two parts on its own. When there are more roles than voices, the remaining roles show **Choose Voice**. If you pick a voice that someone else already speaks with, the app asks first – listeners can only tell the roles apart by their voices.
- **Don't read** leaves a role out on purpose.
- As long as a role has no voice, the audiobook cannot be created – so no lines go missing unnoticed.

## A new voice

**New Voice…** at the bottom of every voice menu builds a voice in VoiceStudio from a few traits: gender, age, pitch and whispering. **Listen** plays the first line of the role, **Other Variant** gives a different voice with the same traits. **Save Voice** stores it in VoiceStudio and gives it to the role.

## Check the text

The right column shows the script as it will be read. Right-click a paragraph to have it **read by the narrator**, **not read**, or back **as detected**.

## Create the audiobook

Choose the **voice language** at the bottom (Automatic, German or English), then click **Create Audiobook…** and choose where to save it. The result is an `.m4b` audiobook with one chapter per scene.

- Making an audiobook takes long: roughly seven times the playing time on an Apple Silicon Mac – a 90-minute script takes about ten hours. Let it run overnight.
- **Pause** stops VoiceStudio; finished scenes are kept, **Resume** continues where it stopped. **Cancel** throws the half-made audiobook away.

## Settings

**Read my Script → Settings…** (⌘,):

- **General:** light or dark look, language (the app restarts).
- **Updates:** version, check for updates, test versions. A notice at the top of the window offers new versions; installing restarts the app.
- **Support:** a self-test with invented test scripts (nothing is sent), the log file, and a coffee if you like the app.
- **About:** version, license and source code.
