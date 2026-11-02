# Margin

A native iPhone app (Swift + SwiftUI, iOS 17+, German UI) for school life: handwritten notes in your own handwriting, a school planner and calendar, and an exam-prep assistant.

It is built entirely from Windows. You never need a Mac or Xcode on your own computer. GitHub rents a Mac in the cloud for each build.

```
 Your Windows PC            GitHub                          Your iPhone
 ───────────────            ──────                          ───────────
 edit Swift files  ──push──▶ Mac runner:                    
 in VS Code                 1. XcodeGen makes the project
                            2. xcodebuild compiles the app
                            3. packs an unsigned .ipa  ──▶ download ──▶ Sideloadly signs it
                                                                        with your Apple ID
                                                                        and installs it
```

## Where we are

| Phase | What | Status |
|---|---|---|
| 0 | Build pipeline proof: one screen, icon, CI, unsigned .ipa | ✅ Tested on iPhone |
| 1 | Navigation, Today screen, subjects, timetable, tasks, exams, calendar, reminders, settings, backup | ✅ Tested on iPhone |
| 2 | Handwriting studio: capture, profile, analysis, rendering, note editor, paper styles, PDF export, notes library | **Built, waiting for you to test on the iPhone** |
| 3 | Exam planner: topics, understanding tracker, roadmap, readiness | Not started |
| 4 | AI learning assistant | Not started |
| 5 | Polish | Not started |

Each phase starts only after the previous one builds and you've tested it on your iPhone. The plan and the technical decisions (including how the handwriting will work, honestly) are in [docs/ROADMAP.md](docs/ROADMAP.md).

The app's interface is **German** (dates, Monday-first weeks, German school terms).

### Phase 2: what to check on your iPhone

Install over Phase 1 – your data is migrated to the new database version automatically. To be safe, **save a backup first** (Einstellungen › Backup sichern).

1. **Handschrift einrichten:** tab *Notizen* › *Handschrift einrichten*. Write each character with your finger on the guide lines (solid line = baseline, dashed = top of small letters). At the end write the word "Handschrift" in one go – it measures your letter spacing. Takes ~10 minutes; you can stop with *Fertig* and continue later ("Fehlende Zeichen schreiben").
2. **Vorschau & Analyse:** the profile shows the pangram in your handwriting, how much the size was corrected, your slant, how even your letters are and which ones stand out. Try *Größe automatisch angleichen* if it lists any.
3. **Varianten:** *Varianten häufiger Buchstaben schreiben* (e, n, i, s, r …, two more each). Repeated letters then stop looking copied.
4. **Einzelne Zeichen korrigieren:** tap a character in the grid – adjust size and height, delete a bad version, write another.
5. **Feinabstimmung:** letter spacing, word spacing, slant and "Natürliche Variation" sliders with live preview.
6. **Notiz:** *Notizen* › new note. Type or paste text. Use the keyboard bar for headings (`#`), subheadings (`##`) and lists (`-`). Switch to *Handschrift* to see the pages.
7. **Papier & Stift:** lined / squared / dotted / blank, line spacing, writing size, pen colour and weight, margins, page numbers, subject & date header. Changes show live behind the sheet. *Neu mischen* gives a different natural variation.
8. **Text bearbeiten:** go back to *Text*, change a word – the pages are re-rendered, nothing is lost.
9. **Import:** the ↓ button: a PDF with text, a scanned PDF or a photo of a worksheet (text recognition on the iPhone, German), a .txt / .rtf file, or the clipboard.
10. **PDF:** *PDF* shows the preview; *Teilen oder sichern* saves it to the Files app or shares it. Check it prints at A4.
11. **Bibliothek:** search, sort by subject / folder / exam, long-press to rename, duplicate, export or delete. Subject pages now list their notes too.

Honest limits of this version: letters are placed one by one (no joined-up cursive yet); characters you haven't written appear in a visibly different fallback font; importing handwriting from a photo of a page is not in this phase (see the roadmap).

### Phase 1: what to check on your iPhone

Installing over Phase 0 is fine (Phase 0 had no data).

1. **Fächer:** on "Heute" tap **Fächer auswählen**, pick a few subjects, add one of your own via **Fächer › +**, change its colour, teacher and room. Reorder with **Bearbeiten**.
2. **Stundenplan:** *Fächer › Stundenplan*. Pick a day, tap a free period, choose the subject. Use **Sichern und nächste Stunde** to fill a whole day quickly. Check the times under *Einstellungen › Stundenraster* match your school.
3. **Heute:** shows the current or next lesson, today's timetable, tasks due by tomorrow, and exams in the next 4 weeks.
4. **Aufgaben:** create a homework with subtasks and an attachment (photo or PDF). Try **Zur nächsten Stunde** for the due date. Tick it off (swipe right or tap the circle). Check the Offen / Überfällig / Erledigt filters.
5. **Prüfungen:** add one from + on Heute or on a subject page. It shows on Heute, on the subject page and in the calendar.
6. **Kalender:** month view (swipe to change month, dots for exams, tasks and events), week view, and day view (timeline with the red "now" line). Add a weekly recurring event. Long-press an entry in the month list to move it by a day or a week.
7. **Ferien:** *Einstellungen › Ferien und freie Tage*. Lessons disappear on those days.
8. **Erinnerungen:** allow notifications, then create a task with a reminder 2 minutes from now and lock the phone.
9. **Backup:** *Einstellungen › Backup sichern* to the Files app, then **Backup wiederherstellen** from that file.
10. **Dark mode** and **Erscheinungsbild** in Settings.

Known Phase 1 limits: rescheduling is via edit or long-press (no drag and drop yet); editing a recurring event changes the whole series; exams don't have topics or a learning plan yet (Phase 3).

---

## Step-by-step guide (for beginners)

### 1. Prepare Windows (one time)

1. **Install Git:** download from <https://git-scm.com/download/win> and run the installer. The default options are fine. When it asks about line endings, keep the default ("Checkout Windows-style, commit Unix-style").
2. **Install Visual Studio Code:** <https://code.visualstudio.com>. Optionally install the "Swift" extension (by the Swift Server Work Group) for syntax colours. It can't compile iOS apps on Windows, and that's fine. GitHub does the compiling.
3. **Tell Git who you are.** Open *Git Bash* (installed with Git) and run:
   ```bash
   git config --global user.name "Your Name"
   ```
   ```bash
   git config --global user.email "you@example.com"
   ```
4. **Create a GitHub account** at <https://github.com> if you don't have one.

### 2. Create the GitHub repository

1. Go to <https://github.com/new>.
2. Repository name: `Margin`.
3. Choose **Private** or **Public** (read the note below).
4. Do **not** tick "Add a README", ".gitignore" or "license". This project already has them.
5. Click **Create repository**.

> **Build minutes, honestly:** Mac builds use GitHub Actions minutes. **Public** repositories get them free. **Private** repositories on a free account get a monthly allowance, and Mac minutes count about **10×**. One Margin build takes roughly 4–8 real minutes, so a private repo allows only a few dozen builds a month (shared with your other private repos, like Orbit). You can check usage at GitHub → Settings → Billing. The code contains no secrets either way: API keys are never stored in the repo.

### 3. Upload (push) the project

Open Git Bash in the `Margin` folder (right-click the folder → "Open Git Bash here") and run these one at a time. Replace `YOUR-USERNAME` with your GitHub username.

```bash
git init -b main
```
```bash
git add .
```
```bash
git commit -m "Phase 0: build pipeline"
```
```bash
git remote add origin https://github.com/YOUR-USERNAME/Margin.git
```
```bash
git push -u origin main
```

The first push opens a browser window to sign in to GitHub. After that, Windows remembers you.

If `git init` says the folder is already a repository, that's fine. Carry on with the next command.

### 4. Run the build on GitHub Actions

- **Automatic:** every `git push` to `main` starts a build.
- **Manual:** on GitHub open your repo → **Actions** → **Build iOS** (left side) → **Run workflow** → **Run workflow**.

A build takes about 4–8 minutes. A green tick means success and a red cross means failure (see [When a build fails](#when-a-build-fails)).

### 5. Download the .ipa

1. Open the repo → **Actions** → click the finished (green) run.
2. Scroll down to **Artifacts**.
3. Click **Margin-0.1.0-build-N**. It downloads as a `.zip`.
4. Right-click the zip → **Extract All**. Inside is `Margin-0.1.0-build-N.ipa`. That's the app.

You must be signed in to GitHub to download artifacts. They're kept for 30 days.

### 6. Install with Sideloadly

The .ipa from GitHub is **unsigned**. An iPhone refuses unsigned apps. Sideloadly signs the app with your free Apple ID on your PC, then installs it.

1. **Install iTunes and iCloud from Apple's website, not the Microsoft Store.** Sideloadly needs Apple's drivers from these versions:
   - iTunes: <https://www.apple.com/itunes/download/win64> (64-bit)
   - iCloud: search "iCloud for Windows download" on apple.com support. If you only find the Microsoft Store version, check Sideloadly's FAQ for the current direct link.
2. **Install Sideloadly** from the official site only: <https://sideloadly.io>.
3. Connect your iPhone with a USB cable. Unlock it and tap **Trust** when it asks "Trust This Computer?".
4. Open Sideloadly:
   - Your iPhone should appear in the **iDevice** dropdown.
   - Drag the `.ipa` file onto the big IPA icon.
   - Type your **Apple ID** email.
   - Click **Start**, enter your Apple ID password and, if asked, the two-factor code shown on your iPhone.
5. Wait for "Done". The Margin icon appears on your home screen.

### 7. Turn on Developer Mode (iOS 16 and newer, one time)

The first time you open a sideloaded app, iOS may say Developer Mode is required.

1. Open **Settings → Privacy & Security**.
2. Scroll to the bottom and tap **Developer Mode**. The option only appears after a sideloaded app has been installed.
3. Turn it on. The iPhone asks to **Restart**, so let it.
4. After the restart, unlock the iPhone and tap **Turn On** in the pop-up, then enter your passcode.

### 8. Trust your developer profile (first install)

If tapping the app shows "Untrusted Developer":

1. Open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your Apple ID email.
3. Tap **Trust "…"**, then **Trust** again.

Now Margin opens.

### 9. Updating to a new build

1. Push your changes (or let me push them), wait for the green build, and download the new artifact.
2. In Sideloadly, drag in the new `.ipa` and press **Start** with the same Apple ID.
3. It installs **over** the existing app. **Your data stays**, because the bundle ID stays the same.

**Never delete the app from your iPhone before reinstalling.** Deleting an app deletes all its data. From Phase 1 on there will be an export/backup function in Settings.

### Free Apple ID limits (important)

- **Apps expire after 7 days.** After that Margin won't open until you reinstall it. Reinstall the same `.ipa` with Sideloadly before the 7 days are up (or any time after) and your data is kept. Sideloadly also has an automatic refresh option, which needs the PC on and the iPhone on the same Wi-Fi.
- **Max. 3 sideloaded apps at once** per free Apple ID. Orbit counts as one.
- **Max. 10 new app IDs per 7 days.** Don't change the bundle ID (`com.hrvsuliman.margin`) for no reason.
- **Some Apple services need a paid developer account (99 €/year):** iCloud sync, push notifications from a server, and sharing data with widgets through App Groups. Local notifications (reminders), on-device storage, the Keychain, PDF export and the Files app all work with a free account. That's why iCloud sync stays in "later".

---

## When a build fails

1. Open the failed run on GitHub and click the red step (usually **Build for iPhone**).
2. Expand **Compiler errors**. That's usually the actual problem.
3. For the whole picture, download the **build-log** artifact from the bottom of the run page. It contains `build.log` (and `test.log`).
4. Send me the complete `build.log` (or the error section). I'll fix the actual cause rather than rewriting working code.

**Unit tests** run after the .ipa is uploaded. If only "Run unit tests" fails, the .ipa is still fine to install.

## Project layout

```
Margin/
├─ project.yml                 XcodeGen definition (replaces the .xcodeproj)
├─ .github/workflows/
│  └─ build-ios.yml            The cloud build: project → compile → .ipa → tests
├─ Margin/                     The app's source code
│  ├─ App/                     App entry, tabs, sheet routing
│  ├─ DesignSystem/            Colours, rows, shared UI pieces
│  ├─ Models/                  SwiftData models (subjects, lessons, tasks, exams …)
│  ├─ Persistence/             Database setup + migrations, attachments, backup
│  ├─ Services/                Calendar maths, timetable, reminders, text import (no UI)
│  ├─ Handwriting/             Stroke storage, analysis, ink outlines, font, page layout, PDF
│  ├─ Settings/                User preferences (school type, bell schedule …)
│  ├─ Features/                One folder per area: Today, Calendar, Subjects, Tasks, Exams, Notes, Handwriting, Settings
│  ├─ Support/                 German dates and formatting, build info
│  └─ Resources/Assets.xcassets  App icon
├─ MarginTests/                Unit tests (run on a simulator in CI)
├─ Design/make_icon.py         Draws the placeholder icon (python Design/make_icon.py)
└─ docs/ROADMAP.md             Phases and technical decisions
```

`Margin.xcodeproj` is **not** in Git. It's generated fresh on every build from `project.yml`. New `.swift` files inside `Margin/` are picked up automatically, so you never have to "add them to the project".

## Technical facts

- Swift 6 compiler in Swift 5 language mode, built with Xcode 16.4 on GitHub's `macos-15` runner.
- Minimum iOS: 17.0. iPhone only, portrait.
- Bundle ID: `com.hrvsuliman.margin`.
- No third-party libraries.
