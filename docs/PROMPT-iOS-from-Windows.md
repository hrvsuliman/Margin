# Prompt: build a native iPhone app from a Windows PC

Copy everything below the line into a new chat and replace the parts in [brackets].

---

I want to build a real, native iPhone app called [APP NAME] with Claude Code, from a **Windows PC only** (no Mac). I install it on my iPhone with **Sideloadly** and a **free Apple ID**. Set it up exactly like this proven setup:

**What the app should do:** [describe the app, the screens, the language of the UI, who it's for]

**Tech (non-negotiable):**
- Swift + SwiftUI, iOS 17+, SwiftData for storage (local only by default), Swift 5 language mode (`SWIFT_VERSION: "5.0"`) to avoid strict-concurrency errors.
- No Expo, React Native, Flutter, web views or cross-platform wrappers.
- No secrets in the repo: API keys only in the iOS Keychain, typed in by me inside the app.

**Project setup (no Xcode on my PC):**
- Use **XcodeGen**: a `project.yml` at the repo root generates the Xcode project in CI. Don't commit `.xcodeproj`.
- Use `GENERATE_INFOPLIST_FILE: YES` with `INFOPLIST_KEY_*` build settings (camera, microphone and other usage texts). Merge extra keys (document types, URL schemes, background modes) from a small `Config/Info.plist` via `INFOPLIST_FILE`.
- App icon in `Assets.xcassets` (a single 1024×1024 PNG is enough).
- A unit-test target (`TEST_HOST`/`BUNDLE_LOADER` pointing at the app) so `@testable import` works.

**Build pipeline: GitHub Actions on a macOS runner:**
- Repo on GitHub. **Make it public**: macOS minutes are free and unlimited for public repos. A private repo burns its free minutes fast, because a Mac minute counts 10×.
- `.github/workflows/build-ios.yml`, triggered on push to `main` and `workflow_dispatch`:
  1. Use the newest Xcode on the runner (`xcode-select` to the highest `/Applications/Xcode_*.app`).
  2. `brew install xcodegen && xcodegen generate`.
  3. `xcodebuild -scheme [App] -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CURRENT_PROJECT_VERSION=${{ github.run_number }}`. On failure, print the compiler errors (`grep -A3 "error:"`) and upload the full log as an artifact.
  4. Check the `.app` (arm64 binary, `Assets.car` present).
  5. Package an **unsigned IPA**: `Payload/[App].app` zipped as `[App]-<version>-build-<n>.ipa`, uploaded as an artifact (`compression-level: 0`).
  6. Only *after* the upload, run the unit tests on a simulator (pick one from `xcodebuild -showdestinations`, retry 3×, fall back to `simctl`), so a failing test never blocks getting an IPA.
- Add a `runner` input (choice: `macos-26`, `macos-15`, `macos-15-intel`) and use `runs-on: ${{ inputs.runner || 'macos-26' }}`. When GitHub has no capacity for one runner type, start the build by hand on another.
- The IPA is ready after about 4–5 minutes; the tests take longer.

**How you (Claude) work:**
- Use the `gh` CLI: push, trigger builds (`gh workflow run … --ref <branch>`), wait for them, read the failed logs (`gh run view --log-failed`), fix and repeat until green. Then download the IPA (`gh run download`) and send it to me.
- Work in phases. Each phase goes on its own branch (`phase-N`) and gets merged into `main` only when the build is green and I've tested it on my iPhone. Bump `MARKETING_VERSION` per phase.
- I can't run Xcode or a simulator myself, so you can't see the app either. Write unit tests for the logic, be honest about what is untested on a device, and give me a short checklist of what to try on the iPhone after each build.
- Python helper scripts for multi-file edits: use raw strings (`r'''…'''`) so `\n` in Swift code isn't turned into real newlines. Long bash heredocs on Windows Git Bash can break; write the script to a file first.
- SwiftData: every property gets a default, relationships are optional, and every schema change is a new `VersionedSchema` with a lightweight migration stage. Add new models instead of changing existing ones.

**Installing (explain this to me step by step, I'm a beginner):**
- Download the `.ipa` from the Actions run, open **Sideloadly** on Windows (iTunes and iCloud from Apple's website, not the Microsoft Store versions), connect the iPhone by USB, drag in the IPA, sign in with my Apple ID.
- On the iPhone: Settings › Privacy & Security › **Developer Mode** on (once). Settings › General › VPN & Device Management › trust my Apple ID (first install).
- Free Apple ID limits: the app expires after **7 days** (re-install with Sideloadly; the data stays), at most 3 sideloaded apps, no iCloud/CloudKit, no push notifications. Local notifications work. App extensions (widgets) and App Groups may not work with a free ID; test before relying on them.

**Alternatives you should know but not use by default:**
- **xtool** (github.com/xtool-org/xtool) builds iOS apps on Linux/WSL without a Mac. It needs a SwiftPM-only project, an Xcode.xip download (~10 GB), USB passthrough (usbipd) and an Apple ID login via private APIs. It **can't build SwiftData apps** (`@Model`/`#Predicate` are closed-source macros) and asset catalogs are shaky on WSL. Only consider it for a small SwiftPM app without SwiftData.
- Codemagic (500 free Mac minutes per month) if the repo must stay private.

Start with Phase 0: the smallest app that proves the pipeline (one screen, icon, CI, unsigned IPA that installs via Sideloadly). Then propose the phase plan for the real app.
