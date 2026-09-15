# Getting OwnAlarm onto your iPhone — from Windows

**You cannot compile an iOS app on Windows.** Xcode is macOS-only; there is no port,
no emulator, no cross-compiler. That part is not negotiable.

**But you do not need to own a Mac.** GitHub rents you one for free, per build. The
route below builds on their macOS runner and installs from your PC over USB.

```
your PC  ──push──►  GitHub macOS runner  ──.ipa──►  your PC  ──USB──►  iPhone
  (edit)              (compiles)            (download)      (Sideloadly signs)
```

Total cost: nothing. Total time: about 20 minutes the first time.

---

## Step 1 — Put the project on GitHub

From `D:\Ronnachai\OwnAlarm`:

```bash
git init
git add .
git commit -m "OwnAlarm: design and iOS app"
```

Create an empty repo on github.com (private is fine), then:

```bash
git remote add origin https://github.com/YOUR-NAME/OwnAlarm.git
git branch -M main
git push -u origin main
```

## Step 2 — Let GitHub build it

The push triggers `.github/workflows/ios.yml` automatically. On the repo's
**Actions** tab you will see *Build OwnAlarm* running two jobs: the model tests on
Linux, and the app build on macOS.

It generates the Xcode project from `ios/project.yml` with XcodeGen — which is why
there is no `.xcodeproj` in the repo and why you never needed a Mac to create one.

When it finishes, download **OwnAlarm-unsigned-ipa** from the run's Artifacts
section. Unzip it; inside is `OwnAlarm-unsigned.ipa`.

**Branches:** work lands on `dev`, which does not build. A `feature/…` branch builds
and runs every test on each push, so its result is waiting even with the computer off. Every push to `uat` builds
the `.ipa` and runs all the tests — the `.ipa` is under that run's Artifacts — so
merging `dev` into `uat` is how a test build is made. Merging into `prod` is the
deploy: the same pipeline and then, only if every test passes, a **GitHub Release**
with the `.ipa` attached. Take tested builds from the repo's **Releases** page;
release files do not expire, artifacts go after 30 days. Each build carries its own
build number (the run number), so iOS treats every install as new.

## Step 3 — Install it on your iPhone

The .ipa is unsigned, so it needs your Apple ID attached before iOS will run it.
**Sideloadly** does that on Windows.

1. Install **iTunes** — the version from apple.com, *not* the Microsoft Store one.
   Sideloadly needs the drivers it installs.
2. Install **Sideloadly** from sideloadly.io.
3. Plug the iPhone in over USB and tap **Trust** on the phone.
4. Open Sideloadly, drag `OwnAlarm-unsigned.ipa` onto it, enter your Apple ID, press
   **Start**. It signs the app with a free development certificate and installs it.
5. On the phone: **Settings ▸ General ▸ VPN & Device Management ▸** your Apple ID **▸
   Trust**.
6. Launch OwnAlarm.

*Alternative:* **AltStore** does the same thing and can refresh apps over Wi-Fi
automatically, which saves you the weekly reinstall below. More setup, less chore.

---

## What free signing costs you

| | Free Apple ID | Paid ($99/yr) |
|---|---|---|
| App expires after | **7 days** — reinstall weekly | 1 year |
| Apps sideloaded at once | 3 | unlimited |
| TestFlight | no | yes |
| **Selling the membership** (in-app subscription) | **no** | set it up in App Store Connect; try it in TestFlight |
| **Critical Alerts entitlement** | **no** | request from Apple |

That last row matters here. Without Critical Alerts an alarm's sound **obeys the
ringer volume and the mute switch**. You will still get:

- alarms firing on time, app closed or open
- a different volume stored and applied per task
- the Lock Screen alert with Stop and Snooze
- fade-in, snooze, repeat days, everything visual

You will *not* get the headline behaviour — 85% ringing through a silenced phone.
That needs the paid account plus Apple approving the entitlement request at
<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>.
Apple grants it for genuine cases (medical, safety, alarms); expect to explain why.

The membership works the same way. A sideloaded build shows the free plan (three
alarms), says the App Store version is needed to subscribe, and keeps every alarm
working. To sell it, create the auto-renewing yearly subscription
`com.ownalarm.app.member.yearly`, at $6 a year, in App Store Connect.

---

## If you would rather just use a Mac for an hour

Sometimes simpler, especially for iterating on UI:

- **MacinCloud** — around $1/hour, browser-based, Xcode preinstalled.
- **Scaleway Mac mini** — hourly, needs a 24h minimum on some plans.
- **A borrowed Mac** — Xcode is free from the Mac App Store.

On any Mac:

```bash
brew install xcodegen
cd ios && xcodegen generate && open OwnAlarm.xcodeproj
```

Then pick your iPhone in the toolbar, set **Signing & Capabilities ▸ Team** to your
Apple ID, and press ⌘R. Same 7-day expiry on a free account.

---

## Iterating after the first install

Edit the Swift files on Windows in any editor, `git push`, wait for the build,
download, re-sideload. Slow, but it works and costs nothing.

If you find yourself doing that more than a few times a week, an hour of cloud Mac
time — or AltStore's automatic Wi-Fi refresh — will pay for itself quickly.
