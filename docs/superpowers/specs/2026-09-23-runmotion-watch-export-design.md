# RunMotion → Apple Watch export tool — design

Date: 2026-09-23 (revised 2026-09-24)
Status: implemented (2026-09-24), pending on-device validation

Revision 2026-09-24: WatchFit is removed from the pipeline. The earlier
assumption that HealthKit/WorkoutKit need a paid Developer Program
account was wrong — the user verified that the HealthKit capability can
be enabled with a free personal team (the Xcode project already carries
the `com.apple.developer.healthkit` entitlement). The tool now builds
the workout itself with WorkoutKit and schedules it straight onto the
Watch. The `.fit` file / Garmin FIT SDK part of the design is dropped.

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
  Apple ID is fine — and is enough for the HealthKit capability that
  WorkoutKit scheduling relies on.
- The user will not touch their Mac as part of the regular workflow.
  Xcode on the Mac is acceptable only for the initial build/install and
  for periodic background re-signing (see Signing & distribution).
- No third-party app in the loop: the tool itself writes the workout to
  the Watch via WorkoutKit. WatchFit is no longer used.
- Parsing must use on-device Apple Intelligence (Foundation Models
  framework), not a cloud/Claude-based service — the user does not want
  to depend on a Claude account for this.
- Screenshot formats vary session to session (different block counts,
  different wording); the tool must not hard-code today's example.

## Goals

- Turn a RunMotion plan screenshot into a structured workout in the
  Watch's Workout app in as few manual steps as possible.
- Let the user pick Tapis vs Extérieur before export.
- Let the user review/correct the parsed steps before anything is
  sent to the Watch.
- Send the workout to the Watch with one tap, with no other app
  involved.
- Never require the paid Apple Developer Program, and never require
  Mac interaction as part of the regular (per-session) workflow.

## Non-goals

- Reading or writing any HealthKit data beyond what WorkoutKit needs to
  schedule a workout plan (no reading of past workouts, heart rate
  history, etc.).
- A watchOS companion app. The workout runs in Apple's own Workout app
  on the Watch.
- Any server component, account system, or cloud AI call.
- Handling activities other than running.
- Producing a `.fit` file or any export format for other apps.

## User flow

1. **First launch (one time)** — user opens the app once; it explains
   the flow and requests WorkoutKit scheduling authorization
   (`WorkoutScheduler.shared.requestAuthorization()`), plus the HealthKit
   authorization prompt if needed.
2. **Capture + Partager** — user screenshots the RunMotion plan (as
   today), then taps Share from Photos (or the screenshot preview) and
   picks the tool from the share sheet.
3. **Lecture + relecture + Tapis/Extérieur** — entirely inside the share
   extension's own UI:
   - On-device OCR (Vision) extracts raw text from the image.
   - On-device Foundation Models session turns that text into a
     structured list of steps (warmup / work / recovery / cooldown,
     each with a duration and, where present, a target speed and/or
     heart rate).
   - A SwiftUI form shows the parsed steps, editable, plus a
     Tapis/Extérieur segmented control above them.
4. **Envoyer à la montre** — user taps "Envoyer". The extension builds
   a WorkoutKit `CustomWorkout`, wraps it in a `WorkoutPlan`, and
   schedules it with `WorkoutScheduler` for today. It appears on the
   Watch in the Workout app's scheduled workouts, ready to start. A
   confirmation is shown and the extension closes.

## Architecture

Single Xcode project (`runmotion_exporter`, iOS deployment target 26.5),
two targets:
- **Container app** (`runmotion_exporter`, already created) — minimal.
  Holds the HealthKit entitlement, shows a one-screen "how to use"
  instruction, and performs the one-time authorization request. Not part
  of the regular flow afterwards.
- **Share extension** (`runmotion_exporterShare`, to add) — the rest of
  the product. Activated by iOS for shared images. Hosts the SwiftUI
  review UI and does the scheduling. Also needs the HealthKit
  entitlement.

No App Group is needed as long as the extension can call
`WorkoutScheduler` itself (see Risks #1 for the fallback if it can't).

### Components

- **`ScreenshotTextExtractor`** — wraps `VNRecognizeTextRequest`
  (Vision, on-device) to turn the shared `UIImage` into raw recognized
  text lines.
- **`WorkoutPlanParser`** — wraps a `LanguageModelSession`
  (Foundation Models, on-device). Prompted with the OCR'd text, returns
  a list of steps: `{type: warmup|work|recovery|cooldown,
  durationSeconds: Int, speedKmh: Double?, speedToleranceKmh: Double?,
  heartRateBpm: Int?}` — using Foundation Models guided generation
  (`@Generable` struct) rather than free-form JSON, so the shape is
  enforced by the framework. The prompt tolerates block count/wording
  varying between screenshots. A generation failure surfaces as
  "couldn't read this screenshot, edit manually" rather than crashing —
  the review screen starts from an empty step list the user can build
  by hand in that case.
- **Review UI (`WorkoutReviewView`)** — SwiftUI form: editable list of
  parsed steps (type, duration, speed range, HR), Tapis/Extérieur
  segmented control, "Envoyer" button.
- **`WorkoutKitBuilder`** — maps the reviewed steps to a WorkoutKit
  `CustomWorkout`:
  - `activity: .running`; `location: .indoor` for Tapis,
    `.outdoor` for Extérieur.
  - `displayName`: `"RunMotion - Tapis"` / `"RunMotion - Extérieur"`.
  - First `warmup` step → `warmup: WorkoutStep(goal: .time(…))`;
    last `cooldown` step → `cooldown`.
  - Everything in between → `blocks: [IntervalBlock]`. Each consecutive
    work (+ following recovery) pair becomes its own `IntervalBlock`
    with `iterations: 1` (pyramids have different durations per rep, so
    no collapsing into repeated blocks is attempted). Work steps use
    `IntervalStep(.work, …)`, recoveries `IntervalStep(.recovery, …)`.
  - Goal per step: `.time(durationSeconds, .seconds)`.
  - Target: speed range → `SpeedRangeAlert` with
    `(speed − tolerance)…(speed + tolerance)` km/h; heart rate →
    `HeartRateRangeAlert` around the given bpm; neither → no alert
    (free recovery).
  - Validated with `CustomWorkout.supportsGoal`/`supportsAlert` before
    scheduling, surfacing any unsupported combination in the UI.
- **`WatchScheduler`** — wraps `WorkoutScheduler.shared`:
  - Checks `authorizationState`; if not authorized, tells the user to
    open the app once (or requests it directly if possible from the
    extension).
  - Before scheduling, removes any previously scheduled plan carrying
    the same `displayName` (via `scheduledWorkouts` + `remove(_:at:)`),
    so Tapis and Extérieur each keep a single reusable slot on the
    Watch, overwritten by the next export.
  - Schedules the new `WorkoutPlan(.custom(workout))` for today's date.

## Signing & distribution

- Free Apple ID (personal team) in Xcode — no paid account. HealthKit
  capability enabled on both targets (verified to be allowed on a
  personal team).
- Initial build/install over USB from the user's Mac.
- **AltServer**, left running on the Mac, re-signs the installed app
  over Wi-Fi automatically before the free 7-day certificate expires,
  so the user does not need to reconnect the phone by hand as part of
  the normal workflow. Documented as a one-time setup step, not a
  per-session one.

## Risks / open technical questions to resolve early in implementation

1. **WorkoutKit from inside a share extension.** Authorization prompts
   and `WorkoutScheduler` calls from an app extension are not
   guaranteed to behave like in the app. Validate with a throwaway spike
   in the first implementation increment (authorize in the container
   app, schedule a hard-coded plan from the extension). Fallback: the
   extension saves the reviewed steps to an App Group and opens the
   container app, which does the scheduling.
2. **Foundation Models availability at runtime.** Even on a supported
   device, Apple Intelligence may be off in Settings. The parser must
   check `SystemLanguageModel.default.availability` and fall back to an
   empty, manually-editable step list rather than crash or hang.
3. **Scheduled-workout sync to the Watch.** Scheduling is on the
   phone; delivery to the Watch's Workout app is handled by the system
   and may take a moment. Verify on-device that the plan shows up and
   that removing/replacing the previous same-name plan works as
   expected.
4. **Free-team re-signing.** If the 7-day certificate lapses, the app
   stops launching until re-signed; scheduled workouts already on the
   Watch are unaffected.

## Testing approach

- Unit tests for `WorkoutPlanParser`'s mapping from generated output to
  steps against a handful of saved OCR text samples (including today's
  pyramid example and at least one differently-shaped plan) — no live
  Foundation Models call needed for this layer.
- Unit tests for `WorkoutKitBuilder` asserting the produced
  `CustomWorkout` has the expected warmup/blocks/cooldown, durations,
  speed ranges, location and display name, and that it round-trips
  through `WorkoutPlan.dataRepresentation` / `WorkoutPlan(from:)`.
- Manual, on-device verification for what cannot be unit-tested: OCR
  quality on a real screenshot, authorization, and the workout actually
  appearing and running on the Watch.
