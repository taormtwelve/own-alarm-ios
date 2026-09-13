# OwnAlarm — iOS

An alarm app where **volume belongs to the task, not the phone**. Every alarm stores
its own level, fade-in and Silent-mode override, so a medication reminder can stay at
30% while a wake-up sits at 85%.

Built from the approved design canvas. SwiftUI, iOS 16+.

---

## Getting it running

There is no `.xcodeproj` in here — Xcode generates one better than a text file can
describe it. To build:

1. Xcode → **File ▸ New ▸ Project ▸ iOS ▸ App**. Product name `OwnAlarm`,
   interface **SwiftUI**, language **Swift**, minimum deployment **iOS 16.0**.
2. Delete the generated `ContentView.swift` and `OwnAlarmApp.swift`.
3. Drag the `OwnAlarm/` folder from here into the project navigator, ticking
   **Copy items if needed** and **Create groups**.
4. Add four short looping audio files to the target, named exactly as
   `AlarmTone.bundled` expects: `siren.caf`, `marimba.caf`, `soft-bell.caf`,
   `whisper.caf`. CAF/AIFF/WAV, under 30 seconds each — that is a hard limit for
   notification sounds.
5. Build and run.

### Capabilities and Info.plist

| What | Where | Why |
|---|---|---|
| **Critical Alerts** entitlement | Signing & Capabilities, after Apple approves the request | The only way an alarm plays at *its own* volume through Silent and Focus |
| `UIBackgroundModes` → `audio` | Info.plist | Keeps a foreground alarm ringing if the screen locks mid-alarm |
| `NSUserNotificationsUsageDescription` | Info.plist | Shown on the permission prompt |

Critical Alerts is requested from Apple at
<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>.
Until it is granted the app still works — it just falls back to a normal notification
sound, which obeys the ringer and the mute switch. The Settings screen reports the
real status rather than pretending.

---

## How it is put together

```
OwnAlarm/
  OwnAlarmApp.swift        App entry, notification routing
  Design/Theme.swift       Colour tokens, typography, metrics, shared modifiers
  Model/Alarm.swift        Alarm, Weekday, AlarmTone, next-fire logic
  Model/AppSettings.swift  Time format, theme, defaults, time formatting
  Store/AlarmStore.swift   Source of truth; persistence; keeps the schedule in step
  Audio/AlarmScheduler.swift  Notification scheduling — where per-alarm volume lives
  Audio/AlarmPlayer.swift  In-app playback, previews, fade-in
  Views/                   One file per screen, plus Components.swift
```

### Where per-task volume actually happens

Two paths, because iOS has two:

- **App not running** — a terminated app cannot wake up and play audio, so the level
  rides on the notification:
  `UNNotificationSound.criticalSoundNamed(_:withAudioVolume:)`. That API is the whole
  reason the feature is possible; it is also why Critical Alerts matters.
- **App in the foreground** — levels are shares of the iPhone's maximum. While a
  slider is dragged, a tone auditioned, or an alarm rings in the app, `SystemVolume`
  remembers the phone's volume, sets it to the chosen level, and puts it back the
  moment the sound ends (and on the next launch, if the app was closed mid-way).
  `AlarmPlayer` runs at full scale on top under `AVAudioSession(.playback)`, which
  ignores the Silent switch, and ramps with `setVolume(_:fadeDuration:)`. There is
  no public API for system volume: this uses the slider inside `MPVolumeView`, the
  route alarm apps rely on — it works today, but Apple could close it.

### Screens → files

| Design artboard | File |
|---|---|
| Alarms | `Views/AlarmListView.swift` |
| Edit alarm | `Views/EditAlarmView.swift` |
| Sound & loudness | `Views/SoundPickerView.swift` |
| Ringing — in app | `Views/RingingView.swift` |
| Ringing — Lock Screen | *No view.* It is the notification itself — content plus the Stop/Snooze actions in `AlarmScheduler.registerCategories()`. iOS owns that surface. |
| Sounds tab | `Views/SoundsView.swift` |
| Settings tab | `Views/SettingsView.swift` |

---

## Flexible, responsive, accessible

The mockups were fixed 390×844 frames. None of that survived into the code:

- **No fixed frames.** Every screen is a `ScrollView` over a `VStack`, so an iPhone
  SE scrolls what a Pro Max shows at once. Nothing clips.
- **Dynamic Type throughout.** Fonts are declared `relativeTo:` a text style;
  the volume meter and peak meter scale with `@ScaledMetric`. Rows grow in height
  rather than truncating.
- **Layouts that give way.** `ViewThatFits` moves the alarm row's toggle below the
  content at large text sizes, drops the ringing dial to a plain stack on short
  screens, and stacks the sound-source tiles when they need the width. Repeat-day
  pills use an adaptive `LazyVGrid`, so they reflow instead of overflowing.
- **iPad and landscape.** Content is capped at a readable 620pt and centred
  (`.readableWidth()`) rather than stretched across a 12.9" display.
- **Hit targets.** Nothing tappable is under 44pt.
- **VoiceOver.** The volume meter is one element reporting "85 percent", not eleven
  anonymous bars; the slider keeps the real `Slider` underneath so the adjustable
  trait and Switch Control keep working; day pills report selected state.
- **Reduce Motion** removes the pulsing ring on the ringing screen.
- **Light and dark** come from one token table (`Tokens`), resolved per trait, with
  a Light / Dark / Auto override in Settings. Light is the default.

---

## Honest caveats

- **I could not compile this.** There is no Xcode on this machine, so the code is
  unbuilt. Expect a few small fixes on first build — an import, a signature drift
  between SDK versions.
- **`DatePicker` and the Clock setting.** The wheel takes its 12/24-hour cycle from
  the locale, not from an API we control, so `EditAlarmView` hands it a locale with
  the matching hour cycle. It works, but it is a workaround; a custom two-wheel
  picker would be the durable fix if the setting matters a lot.
- **No iOS system sounds.** Apple does not expose the standard tone library to
  third-party apps, so the app ships its own tones plus Music/Files import.
- **Fade-in while terminated.** A notification sound plays at one fixed volume —
  `fadeInSeconds` only ramps for a foreground alarm. A background fade would mean
  chaining several notifications at rising volumes, which is doable but noisy.
- **Ringing on the Lock Screen needs iOS 26.** There, alarms go through AlarmKit:
  full screen, sounding until stopped, through Silent and Focus. AlarmKit has no
  volume parameter, so each task's level is baked into a scaled copy of its sound
  (`ScaledSound`) and plays relative to the phone's alarm level. On iOS 16–25 the
  app falls back to notifications, which play once (30 s at most) and stay silent
  in Silent mode without the Critical Alerts entitlement.
- **Snooze is a fresh notification**, not a pause. Cancelling it is handled, but the
  user tapping Snooze from the Lock Screen relies on the action handler running
  promptly.
- **Audio files are placeholders** — the four names must exist in the bundle or
  playback asserts in debug.
