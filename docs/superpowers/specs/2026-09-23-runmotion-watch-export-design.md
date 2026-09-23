# RunMotion → Apple Watch export tool — design

Date: 2026-09-23
Status: approved, pending implementation plan

## Problem

RunMotion Coach (running-plan app) only exports structured sessions to a
watch when the user is on Premium. The user is on the free tier and does
not want to subscribe. They do want their daily plan, shown as a
screenshot inside the RunMotion app, to end up as a structured interval
workout on their Apple Watch (Series 12, watchOS 27), reusable session
after session, with a choice between a treadmill ("Tapis") and an
outdoor ("Extérieur") run.

Constraints settled during brainstorming:
- No Apple Developer Program account (paid, $99/yr). A free personal-team
  Apple ID is fine.
- The user will not touch their Mac as part of the regular workflow.
  Xcode on the Mac is acceptable only for the initial build/install and
  for periodic background re-signing (see Signing & distribution).
- No third-party app should read/write HealthKit or WorkoutKit on the
  user's behalf beyond WatchFit, which already does this and is already
  signed/distributed — the new tool must not need HealthKit/WorkoutKit
  entitlements itself (those require a paid account and were the reason
  an earlier "direct to Watch" design was rejected).
- Parsing must use on-device Apple Intelligence (Foundation Models
  framework), not a cloud/Claude-based service — the user does not want
  to depend on a Claude account for this.
- Screenshot formats vary session to session (different block counts,
  different wording); the tool must not hard-code today's example.

## Goals

- Turn a RunMotion plan screenshot into a `.fit` structured-workout file
  in as few manual steps as possible.
- Let the user pick Tapis vs Extérieur before export.
- Let the user review/correct the parsed steps before anything is
  exported.
- Hand the finished file to WatchFit with one tap, without a separate
  step to open WatchFit manually first.
- Never require the paid Apple Developer Program, and never require
  Mac interaction as part of the regular (per-session) workflow.

## Non-goals

- Talking to HealthKit, WorkoutKit, or the Watch directly. WatchFit
  remains the last step of the pipeline and owns that part entirely.
- Any server component, account system, or cloud AI call.
- Handling activities other than running.
- Guaranteeing WatchFit's own overwrite/dedup behavior when a file of
  the same name is re-imported — that is WatchFit's behavior, outside
  this tool's control (see Risks).

## User flow

1. **Capture + Partager** — user screenshots the RunMotion plan (as
   today), then taps Share from Photos (or the screenshot preview) and
   picks the tool from the share sheet.
2. **Lecture + relecture + Tapis/Extérieur** — entirely inside the share
   extension's own UI:
   - On-device OCR (Vision) extracts raw text from the image.
   - On-device Foundation Models session turns that text into a
     structured list of steps (warmup / work / recovery / cooldown,
     each with a duration and, where present, a target speed and/or
     heart rate).
   - A SwiftUI form shows the parsed steps, editable, plus a
     Tapis/Extérieur segmented control above them.
3. **Export vers WatchFit** — user taps "Exporter". The extension
   builds a `.fit` file and immediately presents the system share
   sheet on it. The user taps WatchFit in that sheet, which opens
   directly into its import flow — no separate manual launch of
   WatchFit.
4. **Export vers la montre** — unchanged, inside WatchFit, as today.

## Architecture

Single Xcode project, two targets:
- **Container app** (`RunMotionExporter`) — minimal. Its only job is to
  exist so the share extension is installable, and to show a one-screen
  "how to use" instruction if opened directly (first-run only; the app
  is never part of the regular flow).
- **Share extension** (`RunMotionExporterShare`) — the entire product.
  Activated by iOS for shared images. Hosts the SwiftUI review UI
  described above.

No App Group is needed: the extension does not need to communicate
back to the container app, since it does the OCR → parse → build →
share-sheet hand-off entirely by itself.

### Components (inside the share extension)

- **`ScreenshotTextExtractor`** — wraps `VNRecognizeTextRequest`
  (Vision, on-device) to turn the shared `UIImage` into raw recognized
  text lines.
- **`WorkoutPlanParser`** — wraps a `LanguageModelSession`
  (Foundation Models, on-device). Prompted with the OCR'd text, returns
  a JSON array of steps: `{type: warmup|work|recovery|cooldown,
  durationSeconds: Int, speedKmh: Double?, speedToleranceKmh: Double?,
  heartRateBpm: Int?}`. The prompt explicitly asks for this exact shape
  and tolerates the block count/wording varying between screenshots.
  Decoded with `Decodable`; a decode failure surfaces as "couldn't read
  this screenshot, edit manually" rather than crashing — the review
  screen starts from an empty step list the user can build by hand in
  that case.
- **Review UI (`WorkoutReviewView`)** — SwiftUI form: editable list of
  parsed steps (type, duration, speed range, HR), Tapis/Extérieur
  segmented control, "Exporter" button.
- **`FitWorkoutBuilder`** — builds the FIT file using the official
  **Garmin FIT Swift SDK** (`github.com/garmin/fit-swift-sdk`, added as
  a Swift Package dependency) — `FileIdMessage`, `WorkoutMessage`,
  `WorkoutStepMessage`, mirroring the message/field structure already
  validated in this conversation's Python prototype (`Intensity`,
  `WorkoutStepDuration.time`, `WorkoutStepTarget.speed` with
  `customTargetSpeedLow/High` in m/s, `WorkoutStepTarget.open` for free
  recovery). `sport = running`; `subSport = treadmill` for Tapis,
  `subSport = street` for Extérieur.
- **Export** — writes the built file to a temp URL named
  `runmotion_export_tapis.fit` or `runmotion_export_exterieur.fit`
  (per the Tapis/Extérieur choice), and the in-file workout name is
  likewise `"RunMotion - Tapis"` / `"RunMotion - Extérieur"` — keeping
  the two session types on two independent reusable slots in WatchFit,
  each overwritten by its own next export. Presents
  `UIActivityViewController` on that file URL.

## Signing & distribution

- Free Apple ID (personal team) in Xcode — no paid account.
- Initial build/install over USB from the user's Mac.
- **AltServer**, left running on the Mac, re-signs the installed app
  over Wi-Fi automatically before the free 7-day certificate expires,
  so the user does not need to reconnect the phone by hand as part of
  the normal workflow. Documented as a one-time setup step, not a
  per-session one.

## Risks / open technical questions to resolve early in implementation

1. **Presenting `UIActivityViewController` from inside a share
   extension.** Generally supported, but should be validated with a
   throwaway spike in the first implementation increment before the
   rest of the UI is built on top of it.
2. **Foundation Models availability at runtime.** Even on a supported
   device, Apple Intelligence may be off in Settings. The parser must
   detect this and fall back to an empty, manually-editable step list
   rather than crash or hang.
3. **WatchFit's own overwrite semantics.** Not under this tool's
   control; the fixed per-mode filename/workout name is the only lever
   available. If WatchFit does not dedupe by name, the user manages
   that inside WatchFit as they already do today.

## Testing approach

- Unit tests for `WorkoutPlanParser`'s JSON decoding against a handful
  of saved OCR text samples (including today's pyramid example and at
  least one differently-shaped plan) — no live Foundation Models call
  needed for this layer, decode logic only.
- Unit tests for `FitWorkoutBuilder` asserting the encoded FIT bytes
  round-trip (decode back) to the expected steps, speeds and sub-sport
  — following the same round-trip check already done against the
  Python prototype earlier in this project's history.
- Manual, on-device verification for the two things that cannot be
  unit-tested: OCR quality on a real screenshot, and the actual hand-off
  to WatchFit.
