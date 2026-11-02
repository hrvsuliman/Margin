# Margin roadmap and technical decisions

This file describes **what** gets built in each phase and **how** the hard parts will work, including what is not possible or is harder than it looks.

## Architecture

The code is split by responsibility, so features can grow (and iCloud sync or a PC companion can be added later) without rewrites:

| Folder | Responsibility | Depends on |
|---|---|---|
| `App/` | App entry, root navigation, dependency setup | everything |
| `DesignSystem/` | Colours, typography, paper backgrounds, reusable controls | SwiftUI only |
| `Features/<Name>/` | Screens and their view logic (Dashboard, Subjects, Tasks, Calendar, Studio, Exams, Assistant, Settings) | Models, Services |
| `Models/` | SwiftData `@Model` types (Subject, Topic, Task, Exam, StudySession, NoteDocument, HandwritingProfile, …) | Foundation, SwiftData |
| `Persistence/` | ModelContainer setup, schema versions and migrations, backup/export | Models |
| `Services/Scheduling/` | Roadmap generation, rescheduling, readiness: plain Swift, fully unit-tested | Models (value snapshots) |
| `Services/Handwriting/` | Sample capture, glyph extraction, text layout, rendering | CoreGraphics, PencilKit, Vision |
| `Services/PDF/` | A4 page layout and PDF export, PDF text import | PDFKit, UIKit |
| `Services/AI/` | Provider protocol, prompt building, response parsing, consent | Foundation, Keychain |
| `Services/Notifications/` | Local reminders | UserNotifications |
| `Support/` | Small helpers | Foundation |

Rules:
- Business logic (scheduling, readiness, text layout) is plain Swift that takes values in and returns values out, so it can be unit-tested without the UI.
- Views never talk to the network. Only `Services/AI` does, and only after the user has agreed.
- SwiftData schemas are versioned from Phase 1, so updates never wipe your data.

---

## Phase 0: build pipeline proof ✅ built

One SwiftUI screen, placeholder icon, XcodeGen, GitHub Actions, unsigned `.ipa`, a few unit tests. **Done when** it installs through Sideloadly and the checks in the README pass.

## Phase 1: core app

- Tab navigation: **Today**, **Calendar**, **Subjects**, **Tasks**, plus **Settings**. Notes and Exams join in Phases 2 and 3.
- SwiftData models with schema versioning: `Subject`, `Topic` (nested subtopics), `Lesson` (timetable slot, weekly recurrence, A/B weeks optional), `SchoolTask` (type, status, priority, due date, estimate, subtasks, attachments), `CalendarEvent`.
- Today screen: today's lessons, due and overdue tasks, upcoming deadlines. It only shows sections that have content, with no filler charts.
- Subjects: create, edit, colour, teacher, topics/subtopics, and the subject page with its lessons, tasks and topics.
- Tasks: open / done / overdue, filters by subject and type, subtasks, attachments via the Files picker.
- Calendar: month, week and day views, Monday first, German date formats by default; tap a day to see everything on it; recurring lessons.
- Local notifications for task and event reminders.
- Settings: school type, lesson times, first weekday, export/import backup (JSON) to the Files app.
- **Open question for you:** should the app's language be **German** or **English**? Both are possible with a String Catalog. We pick one primary language now.

## Phase 2: handwriting studio

This is the hardest and most unusual part, so here's what is and isn't realistic.

### Font file vs. own glyph renderer

**Option A: generate a real font (.ttf/.otf) from your samples.**
- iOS has no API that *creates* fonts. We'd have to write the binary font tables (outlines, character map, metrics) ourselves. That's doable, but it's a lot of work for the result it gives.
- A font draws every "e" identically. OpenType alternates can cycle between a few versions, but a font can't wobble the baseline, rotate single letters or vary spacing naturally.
- **Verdict:** not for the first version. It's a useful *later* feature: "export my handwriting as a font" for Word on the PC.

**Option B: own vector glyph renderer. Chosen for v1.**
- You write each character on screen. We store the **strokes** (points with timing and pressure), not a picture.
- Each character is normalised into a box with baseline, x-height and cap height, so letters written at different sizes line up.
- You write **several versions** of common letters (for example 3 × "e"). The renderer picks between them.
- Our own layout engine places the glyphs: word wrap, letter widths from the real glyph shapes, word spacing, simple kerning.
- Natural variation from a **seeded** random generator: small baseline drift, ±1–2° rotation, ±3 % size, slight spacing changes. The seed is stored with the document, so the same text always looks the same, and editing one word doesn't reshuffle the whole page.
- Strokes are vectors, so pen colour, thickness and size can change at any time, and PDFs stay sharp and small.

### Honest limitations

- **Apple Pencil does not work on iPhone.** Only iPad supports it. On iPhone you write with your finger (or a cheap capacitive stylus). The capture screen gives you a large writing box to make this easier.
- **Joined-up cursive is very hard.** Connecting letters convincingly is a research problem. Version 1 renders **separate letters** (print style). Later we can capture common **letter pairs** as one unit ("ch", "ck", "sch", "ei", "ie", "st"), which makes German text look much more natural.
- **Photo import has to be structured.** Recognising *what* is written (OCR) is easy with Apple's Vision. Cutting a free-written page into individual letters reliably is not, because letters touch and vary. The realistic approach: the app produces a **printable template sheet** with boxes (and corner markers). You print it, fill it in by hand, and photograph it. The app straightens the photo, knows exactly which box holds which letter, and traces the ink into vector outlines (Vision contour detection). That comes after on-screen capture works.
- It will look like *your* letters, but a trained eye will notice it's assembled. The goal is "clearly my handwriting at a glance", not forgery-grade.

### Character set

A–Z, a–z, 0–9, Ä Ö Ü ä ö ü ß, punctuation including German quotes „ “ and – … § € %. Missing characters fall back gracefully (for example ä = a + two dots, if you haven't written ä).

### Documents

- A `NoteDocument` stores the **original text and structure** (title, subject, date, headings, paragraphs, lists) plus **layout settings** (paper style, pen colour, size, line spacing, margins, profile, seed).
- The handwritten pages are **always re-rendered** from that, so editing text never destroys anything.
- Paper: lined, squared (5 mm), dotted, blank, at A4 (210 × 297 mm).
- PDF export: vector PDF via `UIGraphicsPDFRenderer`, saved to Files or shared.
- Text import: paste, type, or import a PDF (text PDFs via PDFKit; scanned PDFs via Vision OCR with German support).

## Phase 3: exam planner

- `Exam` with date, subject and topics. Each topic has description, priority, estimated time, **understanding** (5 levels, separate from **completion %**), last studied, and notes/materials.
- **Roadmap generator** (pure Swift, unit-tested):
  - Inputs: days left, your available study days and minutes per day, topic difficulty, understanding, estimated time, and **other exams and tasks already in the calendar**.
  - Weak and important topics are scheduled **earlier and more often**. Sessions alternate *learn → practise → review*. The last day before the exam is light revision, and a practice test is placed near the end.
  - It never exceeds your daily limit. If it can't fit, it tells you so instead of silently cramming.
- **Missed sessions:** the rest of the plan is reflowed across remaining days within the daily limit, and you get a warning if it no longer fits.
- **Readiness** combines understanding, practice/quiz results, coverage of all topics and how long ago you studied (knowledge fades). It's not just "tasks ticked off". The app shows *why* (for example "Derivatives: notes done, but last quiz 40 %").
- Study sessions appear in the calendar and can be moved.

## Phase 4: AI learning assistant

- Input: pasted text, PDFs, photos of worksheets (OCR on device first), and your notes.
- Features: explain simply, key terms, summaries, flashcards, practice questions, mock tests, revision sheets, "turn into handwritten notes", answer evaluation, weak-topic recommendations feeding the understanding tracker.
- **Grounding:** the material is sent with the request and the model is instructed to answer only from it and to say clearly when something isn't in the material. Answers show which part of the material they came from.
- **Privacy:** nothing is sent until you've seen a clear screen saying *what* will be sent and *where*. Handwriting samples are never sent.
- **Keys:** you enter your own API key in Settings. It's stored in the iOS **Keychain** on your phone, never in the code or on GitHub.
- **Providers:** a small `AIProvider` protocol, so providers can be swapped. First an online provider (for example Anthropic's Claude API).
- **Offline:** a clear "needs internet" state. Everything else in the app keeps working. Apple's on-device model (Foundation Models framework) could serve as an offline option, but it needs **iOS 26 + an Apple Intelligence iPhone (15 Pro or newer)** and a newer Xcode on the build runner. We'll check that when we get there.

## Phase 5: polish

Animations, haptics, transitions, rendering performance (glyph caching, background rendering), accessibility (Dynamic Type, VoiceOver), empty states, error handling, testing across screen sizes (SE to Pro Max).

## Later

iCloud sync (needs a paid Apple developer account), PC companion, advanced handwriting customisation, font export, more export formats.
