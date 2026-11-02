# Margin

A native iPhone app (Swift + SwiftUI, iOS 17+) for school life: handwritten notes in your own handwriting, a school planner and calendar, and an exam-prep assistant.

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
| 0 | Build pipeline proof: one screen, icon, CI, unsigned .ipa | **Built, waiting for you to test on the iPhone** |
| 1 | Navigation, dashboard, subjects, tasks, local storage, basic calendar, settings | Not started |
| 2 | Handwriting studio: capture, profile, rendering, document editor, PDF export | Not started |
| 3 | Exam planner: topics, understanding tracker, roadmap, readiness | Not started |
| 4 | AI learning assistant | Not started |
| 5 | Polish | Not started |

Each phase starts only after the previous one builds and you've tested it on your iPhone. The plan and the technical decisions (including how the handwriting will work, honestly) are in [docs/ROADMAP.md](docs/ROADMAP.md).

### Phase 0: what to check on your iPhone

1. The app installs and opens without crashing.
2. The home screen icon shows the ruled paper with the red margin line and the "M".
3. The screen shows **Version 0.1.0 (build N)**, where N matches the run number on GitHub.
4. Switch your iPhone between light and dark mode (Control Centre). The paper changes colour and the "Light and dark mode" row updates.
5. Tap **Test haptics**. You should feel a tap. If you don't, check Settings → Sounds & Haptics → System Haptics.

If all five work, the pipeline is proven and we can start Phase 1.

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
│  ├─ App/                     App entry point
│  ├─ DesignSystem/            Colours, paper background, shared UI pieces
│  ├─ Features/                One folder per screen or feature
│  ├─ Support/                 Small helpers (build info, …)
│  └─ Resources/Assets.xcassets  App icon and images
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
