# Testing OwnAlarm

## The blunt version

| What | Where it can run | Why |
|---|---|---|
| Model, scheduling arithmetic, persistence, clock formatting | **This Windows machine** | Pure Foundation — no Apple SDK needed |
| Every screen, the notification scheduling, audio playback | **macOS + Xcode only** | SwiftUI, UserNotifications and AVFoundation ship with the Apple SDKs. There is no Windows port, no emulator, no workaround |
| Silent-switch override, Lock Screen alert, alarm while terminated | **A real iPhone** | The Simulator does not have a mute switch, and its notification behaviour is not faithful |

Xcode has never run on Windows and Apple has no plans to change that. Anything past
the model layer needs a Mac — borrowed, bought, or rented by the hour.

---

## What you can run here, now

```bash
cd ios && swift test
```

This builds `OwnAlarm/Model` as a standalone package (see `Package.swift`) and runs
the suite in `Tests/OwnAlarmCoreTests`. It covers:

- volume rounding and the fade-in floor
- `repeatSummary` for every pattern — Once, Every day, Mon – Fri, Weekends, irregular
- `nextFireDate` landing on a real repeat day at the right hour, staying inside 24h
  for a one-shot, and returning nil when the alarm is off
- JSON round-trips for `Alarm` and `AppSettings` (the on-disk format)
- the starter alarms pointing only at tones that actually ship
- 24-hour vs AM/PM formatting, and `.automatic` following the locale
- the countdown string on the next-alarm banner

That is the logic most likely to be quietly wrong, and it is now covered. It is not
the UI, and it is not the alarm actually going off.

---

## Getting to a Mac

Cheapest first:

1. **A Mac you can borrow.** Xcode is free from the Mac App Store. Any Apple silicon
   Mac handles this project comfortably.
2. **Rented by the hour** — MacinCloud, MacStadium, or an EC2 `mac2.metal` instance.
   Fine for a build and a Simulator run; awkward for iterating on UI.
3. **GitHub Actions** (`runs-on: macos-14`) for builds and tests on every push. Free
   minutes for public repos. This gets you a green/red signal without owning
   hardware, but you never *see* the app.
4. **Xcode Cloud** if you already pay for a developer account.

### Signing

- A **free Apple ID** installs to your own device for 7 days before it expires. Good
  enough to feel the alarm go off.
- The **$99/yr Developer Program** is required for TestFlight, for builds that do not
  expire, and to request the **Critical Alerts** entitlement — without which per-task
  volume cannot exceed the ringer or ring through Silent.

---

## What still has to be tested by hand, on a device

None of this can be automated, and all of it is the actual product:

- [ ] Alarm fires with the app **force-quit** — the real test of the notification path
- [ ] Alarm fires with the phone on **Silent** (needs Critical Alerts granted)
- [ ] Alarm fires inside a **Focus** mode
- [ ] Two alarms at different volumes, back to back — do 30% and 85% actually *sound*
      like 30% and 85%?
- [ ] Lock Screen alert shows **Stop** and **Snooze**, and both work without unlocking
- [ ] **Show on Lock Screen** off → nothing appears on the Lock Screen, alarm still
      takes over when the app is opened
- [ ] Snooze returns at +10% when that setting is on
- [ ] Fade-in ramps rather than jumping (foreground only — see the README caveat)
- [ ] Alarm survives a **reboot** (notifications are re-armed on next launch)
- [ ] Alarm survives a **time-zone change** and a daylight-saving shift
- [ ] Ringing while a **call** is active, and while music is playing

### Accessibility pass

- [ ] Largest Dynamic Type size on an iPhone SE — nothing clipped, nothing unreadable
- [ ] VoiceOver: the volume meter announces a percentage, not eleven bars
- [ ] Reduce Motion: the ringing dial stops pulsing
- [ ] Light and dark, and the Auto setting following the system
- [ ] iPad, portrait and landscape — content stays in a readable column

---

## Suggested CI

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  core:
    runs-on: ubuntu-latest        # model layer needs no Apple SDK
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
      - run: swift test --package-path ios

  app:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild -project ios/OwnAlarm.xcodeproj -scheme OwnAlarm \
               -destination 'platform=iOS Simulator,name=iPhone 15' build
```

The first job is the one that runs today. The second needs the Xcode project you
generate following the README.
