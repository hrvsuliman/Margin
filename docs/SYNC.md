# Margin Sync (protocol v1)

Keeps iPhone, Android and Windows on the same data through **your own** Cloudflare Worker (`connector/`). Everything is encrypted on the device before it leaves; the Worker stores ciphertext it cannot read.

Status: the server side and the Android/Windows client are built. The iPhone app does **not** have a sync client yet – this document is the spec for it.

Sync is **off** until the user turns it on. Before the first upload the app says what will be sent, where to, and that a forgotten passphrase cannot be recovered.

## 1. Keys

Everything comes from one passphrase that only the user knows. It is typed on every device; it is never sent anywhere and never stored. Only the derived key and token are stored on the device.

```
passphrase   = the typed text, leading/trailing whitespace removed, UTF-8 bytes (no Unicode normalisation)
master       = PBKDF2-HMAC-SHA256(passphrase, salt = UTF-8 "margin-sync-v1", iterations = 310000, length = 32)
prk          = HMAC-SHA256(key = 32 zero bytes, message = master)               // HKDF-extract, empty salt
key          = HMAC-SHA256(key = prk, message = UTF-8 "margin-sync-v1 key"   ‖ 0x01)   // 32 bytes, AES-256-GCM
vaultToken   = hex(HMAC-SHA256(key = prk, message = UTF-8 "margin-sync-v1 vault" ‖ 0x01))  // 64 lowercase hex chars
```

`key` and `vaultToken` are two independent HKDF outputs: the token (which the server sees) reveals nothing about the key.

The salt is a constant so that every device derives the same values from the passphrase alone. The cost of that: an attacker who has the server data can try passphrases offline (each guess costs 310 000 PBKDF2 rounds). **The passphrase must be long** – the apps require at least 4 words / 16 characters and offer a generated one. Letters a–z, digits and spaces are safest (no normalisation is done, so an "ä" typed differently on two keyboards would give a different key).

**Test vector** (checked in `connector/test.mjs` and `android-windows/test/sync_crypto_test.dart`):

```
passphrase  "  korrekt pferd batterie heftklammer "   (trimmed before use)
key         5314c46262f08cedf6afdcada238475fa37dab724ff206447c0af0298d91bcca
vaultToken  eb4bb41576e9e67496a94611417ced57ac85c8bca9acee6324ef625b01b9d55d
```

## 2. Records and encryption

Every object (a subject, a task, a note, …) is one **record**:

| Field | Seen by the server | Meaning |
|---|---|---|
| `uid` | yes | The object's UUID, **uppercase** (`8D0B9F5E-2B7C-4C1A-9E3F-1A2B3C4D5E6F`), as Swift's `UUID.uuidString`. 1–64 chars `[0-9A-Za-z-]`. |
| `updatedAt` | yes | Last change, integer milliseconds since 1970 (UTC). Decides conflicts. |
| `blob` | yes (ciphertext) | base64 (standard alphabet, with padding) of `nonce (12 bytes) ‖ AES-256-GCM ciphertext ‖ tag (16 bytes)`. |

The plaintext inside `blob` is UTF-8 JSON:

```json
{ "v": 1, "type": "task", "deleted": false, "data": { "uid": "…", "title": "S. 42 Nr. 3", … } }
```

- Nonce: 12 random bytes, new for every encryption.
- Additional authenticated data: UTF-8 of `"<uid>|<updatedAt>"` (e.g. `8D0B…5E6F|1762160400000`). The server can therefore not move a blob to another uid or change its timestamp – decryption fails. A client that fails to decrypt a record skips it (and shows "n Einträge konnten nicht gelesen werden").
- The type and the deleted flag are inside the ciphertext, so the server cannot tell a task from a note or a delete from an edit. It only learns how many records there are, their sizes and when they change.

Test vector: with the key above, `uid = 8D0B9F5E-2B7C-4C1A-9E3F-1A2B3C4D5E6F`, `updatedAt = 1762160400000`, nonce `00 01 02 … 0b` and plaintext `{"v":1,"type":"task","deleted":false,"data":{"uid":"8D0B9F5E-2B7C-4C1A-9E3F-1A2B3C4D5E6F","title":"S. 42 Nr. 3"}}` the blob is

```
AAECAwQFBgcICQoLgqL/ULm19SQ4qQ4ZIiRuTzyqKi6QXSp/6G3JfKhLQZzMSSL1yj4uClzgkjDoqLGuA9uXosmWg7Q24zfCl9Rc3HEsDCt22BmKn7HVXA+Odp6f7xom4YdfmA6gwER4MdxXbeMbdXKLWW8jQ3Pn8mIaAGFBSwLcatom4r5VSHT9C9lk
```

## 3. Endpoints

Base URL: the Worker, e.g. `https://margin-connector.<name>.workers.dev`. Every request carries `Authorization: Bearer <vaultToken>`. A missing or malformed token → `401`. Each token is its own Durable Object (`"vault:" + token`), separate from the connector's MCP data.

### `POST /e2e/push`

```json
{ "records": [ { "uid": "…", "updatedAt": 1762160400000, "blob": "…" } ] }
```

At most 200 records per request (`413` otherwise), each `blob` at most 1 900 000 characters (≈ 1.4 MB of plaintext). Answer:

```json
{ "accepted": ["…"], "rejected": [ { "uid": "…", "reason": "stale", "updatedAt": 1762160500000 } ], "cursor": 42 }
```

- **Last write wins per record:** a record is stored only if its `updatedAt` is *greater* than the stored one. Otherwise it is rejected with `reason: "stale"` and the server's `updatedAt`; the client keeps its local copy marked as changed and pulls – the newer server version then replaces it.
- `reason: "invalid"` (bad uid/updatedAt/blob) or `"tooLarge"`: the client stops retrying that record and tells the user.

### `GET /e2e/pull?since=<cursor>&limit=<n>`

Every record whose latest version arrived after `cursor` (start with `0`), in arrival order. `limit` defaults to and is capped at 500.

```json
{ "records": [ { "uid": "…", "updatedAt": 1762160400000, "blob": "…", "seq": 43 } ], "cursor": 43, "more": false }
```

Store `cursor` and call again while `more` is `true`. A record that changed several times appears only once, in its latest version.

### `GET /e2e/info`

`{ "records": 123, "cursor": 456 }` – for the settings screen.

## 4. Client algorithm

Local state per device: for every record its `updatedAt` and a `dirty` flag, plus the last `cursor`.

1. **Change locally** → set `updatedAt = max(now, previous + 1)`, mark dirty. A delete keeps a tombstone (`deleted: true`, `data: { "uid": … }`) so the delete can travel.
2. **Sync** (on start, after changes with a short delay, every few minutes while open, and on "Jetzt abgleichen"):
   1. Push dirty records in batches of ≤ 200. Accepted → clear dirty. Stale → leave dirty for now.
   2. Pull from the stored cursor until `more` is false. For each record: decrypt; if its `updatedAt` is newer than the local one, replace the local object (or delete it if `deleted`) and clear dirty; otherwise ignore it (our newer local change will win on the next push).
   3. Store the cursor.
3. Unknown `type`s and unknown fields are **kept as they are** and pushed back unchanged when edited, so an older app never destroys data a newer one wrote.
4. Flashcards that come from `Begriff :: Erklärung` lines are created only by the device on which the note text was edited. A note that arrives through sync does **not** re-create its cards – they arrive as `card` records with their own learning state. (Otherwise two devices would create duplicate cards.)

Clocks: last write wins uses the device clocks. A device whose clock is far off can win or lose wrongly; the apps show a hint if the server's `Date` header is more than 2 minutes away.

Conflicts are per object, not per field: if the same task is edited on two devices before they sync, the later edit wins completely.

## 5. Record types (`type`) and `data` fields

`data` uses exactly the field names of the backup DTOs in `Margin/Persistence/BackupService.swift` (`BackupFile.*DTO`). Rules for all of them:

- Dates: ISO 8601 in UTC **without fractional seconds**, `2026-11-03T08:00:00Z` (what Swift's `JSONEncoder.dateEncodingStrategy = .iso8601` writes and accepts). Days without time (a task's `dueDate` with `hasDueTime = false`, holidays, all-day events) are the start of that day in the device's time zone, converted to UTC.
- References to other objects are uppercase UUID strings or absent/`null`.
- Binary data (photos) is base64, as Swift's `Data` encodes.

| `type` | Swift model | DTO | Fields |
|---|---|---|---|
| `subject` | `SchoolSubject` | `SubjectDTO` | uid, name, colorKey, teacher, room, notes, sortIndex, createdAt |
| `topic` | `Topic` | `TopicDTO` | uid, title, details, sortIndex, createdAt, subject, parent |
| `lesson` | `Lesson` | `LessonDTO` | uid, weekday (1 = Monday … 7 = Sunday), startMinute, endMinute (minutes since midnight), room, note, subject |
| `task` | `SchoolTask` | `TaskDTO` | uid, title, details, kind (`homework` `assignment` `presentation` `project` `examPrep` `general`), priority (0–2), status (`open` `inProgress` `done`), dueDate, hasDueTime, reminderDate, estimatedMinutes, createdAt, completedAt, subject, topic, exam |
| `subtask` | `Subtask` | `SubtaskDTO` | uid, title, isDone, sortIndex, task |
| `exam` | `Exam` | `ExamDTO` | uid, title, kind (`classTest` `klausur` `test` `oral` `finalExam` `other`), date, hasTime, durationMinutes, room, notes, reminderDaysBefore, createdAt, subject |
| `event` | `CalendarEvent` | `EventDTO` | uid, title, notes, location, start, end, isAllDay, category (`personal` `school` `project` `presentation` `trip` `other`), recurrence (`never` `daily` `weekly` `biweekly` `monthly` `yearly`), recurrenceEnd, reminderMinutesBefore, createdAt, subject |
| `holiday` | `Holiday` | `HolidayDTO` | uid, name, start, end |
| `note` | `NoteDocument` | `NoteDTO` | uid, title, body (markup, see below), folder, noteDate, createdAt, updatedAt, subject, topic, exam, profile, paper (`lined` `squared` `dotted` `blank`), lineSpacingMM, writingSize, penColor (`royalBlue` `black` `navy` `green` `red` `violet`), penWeight, marginTopMM, marginBottomMM, marginLeftMM, marginRightMM, showMarginLine, showPageNumbers, showHeader, printPaper, seed |
| `noteMeta` | `NoteMeta` | `NoteMetaDTO` | uid, note, parent, pinned, template |
| `pin` | `PinItem` | `PinDTO` | uid, subject, kind (`note` `video` `link` `photo` `sticky`), title, text, url, note, color (a `SubjectColor` key), sortIndex, createdAt, photo (base64 JPEG, ≤ 1.4 MB, optional) |
| `card` | `Flashcard` | `CardDTO` | uid, subject, topic, note, front, back, createdAt, ease, intervalDays, repetitions, lapses, due, lastReviewed |
| `session` | `StudySession` | `SessionDTO` | uid, exam, topic, subject, kind (`learn` `practice` `review` `mockTest` `finalReview` `free`), status (`planned` `done` `skipped`), date, plannedMinutes, actualMinutes, completedAt, isPlanned, note |
| `progress` | `TopicProgress` | `ProgressDTO` | uid, topic, understanding (0–4), completion (0–1), importance (0–2), estimatedMinutes, lastStudied, updatedAt |
| `plan` | `ExamPlan` | `PlanDTO` | uid, exam, topics ([uid]), dailyMinutes, weekdays ([1–7]), generatedAt, createdAt |
| `result` | `PracticeResult` | `ResultDTO` | uid, topic, exam, subject, score (0–1), date, kind |
| `grade` | `Grade` | `GradeDTO` | uid, subject, exam, title, value, kind (`written` `oral` `test` `other`), weight, date |
| `gradeSetup` | `GradeSetup` | `GradeSetupDTO` | uid, subject, writtenShare, goal |
| `ink` | – (new) | – | uid, note, strokes, createdAt – see below |

Not synced in v1 (stay on the device): handwriting profiles and glyphs, attachments and note images (too large for one record – a chunked `blob` type is the planned v2), lesson recordings, tutor chats, WebUntis entries, settings, API keys. API keys and passwords are never synced.

### Note markup (`note.body`)

Same rules as `NoteBlock.parse` in `Margin/Handwriting/NoteLayout.swift`: `# ` heading, `## ` subheading, `- ` / `• ` / `* ` list item, `- [ ] ` / `- [x] ` checkbox, `> ` callout, `| a | b |` table rows (a `|---|` rule row is ignored), `---` divider, `[[Titel]]` link to another note, `[[Bild:<uid>]]` picture line, and `Begriff :: Erklärung` lines become flashcards.

### `ink` (pen strokes drawn on Android tablets / Windows pen PCs)

One record per note that has ink (`note` = the note's uid).

```json
{
  "uid": "…", "note": "…", "createdAt": "2026-11-03T08:00:00Z",
  "pageWidth": 1000, "pageHeight": 1414,
  "strokes": [ { "tool": "pen", "color": "royalBlue", "width": 2.4, "points": [x0, y0, p0, x1, y1, p1, …] } ]
}
```

- Coordinates are in page units: the page is 1000 wide (A4 ratio, 1414 high); pages are stacked, so `y = 1414 · pageIndex + y on that page`. The same note looks the same on every screen size.
- `p` is the pen pressure 0…1 (0.5 when the device reports none). `width` is the base width in page units; the drawn width is `width · (0.35 + 1.3 · p)`.
- `tool`: `pen` or `highlighter` (drawn at 35 % opacity). `color`: a `PenColor` key or `#RRGGBB`.
- Points are rounded to one decimal to keep records small. A note's ink must stay under the record limit (about 60 000 points); the app warns before that.

The iPhone app does not draw `ink` yet; it should keep the records (rule 3 above) so they are not lost.
