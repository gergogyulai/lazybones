> **Early.** Version 0.3, built around one setup: a MacBook on a TV, run with a Siri Remote (USB-C, 2022). There are no releases, so you build it yourself. The site-specific parts (Netflix navigation, YouTube's TV mode) depend on those sites' markup and can break when it changes.

<div align="center">
  <br>
  <h1>Lazybones</h1>
  <sub>A tvOS-style launcher for streaming sites, for a Mac plugged into a TV</sub>
  <br>
  <br>
</div>

Lazybones turns a Mac connected to a TV into something you run from the couch with a Siri Remote. Every streaming site is a persistent web view with an icon on a Home Screen, so switching away from Netflix and back leaves you where you were. There's no browser chrome, no mouse and no keyboard.

- 📺 A Home Screen with a top shelf, an app grid whose focused icon tilts under your thumb, and a tvOS-style app switcher (swipe up to close an app)
- 🎮 The Siri Remote over USB or Bluetooth: clicks, swipes, long presses, and the volume and power buttons
- 🧭 Remote navigation for any page, chosen app by app: arrow keys for sites with a TV interface, a focus ring for desktop sites, or a cursor you move with touch. Plus custom navigation for sites where that isn't enough (Netflix moves through rows, sliders and the details panel like the TV app)
- ⌨️ An on-screen keyboard that follows whichever text field the page has focused
- 🔊 Volume routing: a volume press changes the Mac, an LG TV (and the soundbar on its ARC port), or the page's own media volume, whichever can actually do it
- 🛡️ Ads blocked with uBlock Origin Lite, app by app, with its own settings in Settings. YouTube's TV app also has the ads taken out of its responses, where uBO Lite's rules don't reach
- ⏭️ SponsorBlock on YouTube, skipping sponsor segments, intros and the like in the TV app too, with its own settings under YouTube in Settings > Apps
- 🌙 Sleep Mode: dims the screen and filters blue light for every display and every app, video included
- 🔈 Navigation sounds, synthesized in code: a warm low "dum" when focus moves, and a "dum-hit" with a brighter, higher note on top when you select (switch them off in Settings > General)
- 🎛️ Control Center (hold the TV button): home, sleep, volume, output and network
- 📡 A page that can't load says why, with Try Again, and tries again by itself once the network is back
- 🧪 A debug overlay showing what each page reports about DRM, codecs and HDR, and an on-screen remote so you can develop without the hardware

Built-in apps: YouTube, Netflix, Disney+, Prime Video, HBO Max, Apple TV, SkyShowtime, Paramount+, Crunchyroll, Twitch, Telekom TV GO, Spotify, Apple Music, YouTube Music, SoundCloud, Plex, Jellyfin and Emby. Two test pages (DRM, ad blocking) sit alongside them for development. You can add any other site in Settings.

## Why

For travelling. At home it's the Apple TV; on the road it's a MacBook and a hotel TV. The laptop and the Apple TV remote are easy to pack, and together they get close enough to the couch: plug in, lie back, use the remote.

### Why "Lazybones"

Lazy Bones was Zenith's 1950 remote, the first TV remote control.

## Status

| Piece | What's there |
|---|---|
| Launcher, app switcher, Control Center, Settings | Home Screen and app switcher, both Settings forms, Control Center |
| Siri Remote | Buttons, touch surface, battery. The USB-C 2022 model only. |
| LG TV control | Pairing, volume, mute, power, discovery. webOS only. |
| Netflix | Its own navigation script, tested against a mock page shaped like Netflix's (the real one needs an account) |
| YouTube | Served its TV interface by presenting as a Sony Bravia, with answers to its codec queries faked like a 4K TV's |
| Other services | The shared navigation, plus per-site tweaks where needed |
| Ad blocker | uBlock Origin Lite, downloaded at build time |
| SponsorBlock | Its Safari build, downloaded at build time. Works on YouTube's TV interface; its on-screen notices can't be reached with the remote, so set categories to skip automatically. |

### Don't expect

- **Other remotes or TVs.** `SiriRemote` only knows the 2022 USB-C Siri Remote's HID usages, and `LGTV` only speaks LG's webOS protocol. Other TVs' volume falls back to the Mac's or the page's.
- **HDMI-CEC.** Macs can't send it, which is why the TV is controlled over the network instead.
- **A signed, notarized app.** The build is ad-hoc signed and runs on the Mac that built it.
- **DRM you can't get in Safari.** Playback goes through WebKit, so a service gets exactly the DRM and codecs Safari gets. The debug overlay shows what a page was given.

## Requirements

- macOS 15.4 or later
- Xcode with Swift 6 (the package uses the Swift 5 language mode)
- A Siri Remote (USB-C, 2022), the Apple TV remote, or the on-screen remote
- A TV or display on HDMI
- Optional: an LG webOS TV on the same network, for controlling its volume and power

## Build and run

```sh
git clone https://github.com/gergogyulai/lazybones.git
cd lazybones
Scripts/build.sh          # release build to build/Lazybones.app (--debug for a debug build)
open build/Lazybones.app
```

The app icon is drawn in code; `swift Scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`. The build downloads uBlock Origin Lite and SponsorBlock on first use (`Scripts/fetch-ubol.sh`, `Scripts/fetch-sponsorblock.sh`; `make ubol` and `make sponsorblock` update them). If that fails, or you pass `--no-ext` at launch, Lazybones still works, just without them. macOS asks for local network access the first time, which is how it finds and talks to the TV.

```sh
swift test                # unit tests
```

Hold the remote's TV button (or ⇧⌘C) for Control Center. ⌥⌘R shows an on-screen remote.

The on-screen remote sits in a window laid out like Xcode's Simulator: its name and state (simulated, or with the real remote connected too) in the title bar beside Keep on Top and an options menu, and a glass bar underneath for the TV button's timed gestures (Home, App Switcher, Control Center) and Siri (the debug overlay). It works like the real one. Click the clickpad's ring for a direction (hold to repeat) or its centre to select, and hold the TV button for Control Center. To swipe, drag on the clickpad, scroll with two fingers anywhere on the remote, or press ⇧ and an arrow key. While a finger rests on the clickpad or the trackpad, the focused icon tilts as it does under a thumb. Each button has its key printed on it. Under the remote is what was just sent (switch it off, or the key labels, in the options menu), including presses from the real remote and `Scripts/ctl.sh`, which also light up their buttons.

> **Why `dev.lull.spike`?** The app was Lull, and before that a prototype called Spike. The bundle identifier is unchanged so saved settings and the TV pairing carry over. It's invisible unless you go looking in `defaults`.

## Using it

Controls, on the remote or the keyboard equivalents in the Lazybones menu:

| Do this | To get |
|---|---|
| Click the TV button | Home. Already Home: back to the first app. |
| Double-click the TV button (⇧⌘A) | The app switcher: select to resume, swipe up to close an app. |
| Hold the TV button, or Power (⇧⌘C) | Control Center. |
| Back | The page before, else Home. Sites with a TV interface get it first (see `WebPool.back`). |
| Up from the first row of apps | The Home Screen's Settings button (⌥⌘, from anywhere). |
| Play/Pause on the Home Screen | Plays or pauses the music left playing (Spotify, Apple Music, YouTube Music, SoundCloud). |

### Settings

Settings come in two forms. The Settings screen on the Home Screen (or in Control Center) is for the remote: apps shown and their order, layout, Sleep Mode, keyboard, TV. Settings on the Mac (⌘,) has the same plus what needs a keyboard: app names, addresses and colors, TV pairing by address, and the extensions' own settings pages: uBlock Origin Lite's dashboard (filter lists, filtering modes, your own filters) and SponsorBlock's options (which segments to skip, mute or mark).

Apps, in both, lists every app; click one for its own settings: whether it's on the Home Screen, its navigation and cursor, and a switch for each extension that works on it, with SponsorBlock's options under YouTube (the only app it works on). Ad Blocking, in both, also switches uBlock Origin Lite on or off for every app at once and holds its dashboard. An app reloads when you change its extensions. The extensions share one controller, since one loaded twice would keep two sets of settings, so an app that switches one off is denied it by address; for uBlock Origin Lite, whose network rules that doesn't stop, the app's site also goes on uBO Lite's own "no filtering" list, where its dashboard shows it.

To pair a TV, pick it from the discovered list (or enter its address) and accept the prompt on the screen. Volume steps reach a soundbar on HDMI ARC through the TV. Outputs with no volume control of their own and no TV fall back to the apps' volume.

### Navigation

Each app gets the remote one of three ways, set in the app's own settings under Settings > Apps (on the TV or the Mac). Sites that handle the remote themselves (YouTube's and Jellyfin's TV interfaces) keep their own.

| Navigation | What the clickpad does |
|---|---|
| Arrow Keys | Goes to the page as arrow keys and Return, for sites with their own TV layout. |
| Focus | Moves a focus ring between the page's links and buttons. Select clicks the one focused. |
| Cursor | Moves a pointer, like a mouse. Select clicks what's under it. |

The cursor is a white dot that eases after your thumb and turns into an outline around the button it's over. Each app has its own cursor settings:

- **Move with touch**: slide a finger like on a trackpad, slow for precision and quick to cross the screen.
- **Move with the clickpad**: click the ring to step, hold it to glide, gathering speed. Turn it off and the page gets arrow keys instead (keep one of the two on).
- **Snapping** (Off, Light, Medium, Hard): how strongly the cursor is drawn onto buttons. Under touch it's pulled toward the button's middle and slows over it. With the clickpad, Medium and Hard make a click hop to the next button in that direction, as Focus does.
- **Size** and **speed** for touch and the clickpad.
- **Ring scrolling**: run a finger around the clickpad's edge, as you would to scrub on Apple TV. Clockwise scrolls down (or up, if you'd rather), with its own speed and optional momentum. It scrolls whatever is under the cursor, so a scrolling panel scrolls rather than the page behind it. Pushing the cursor past the top or bottom edge scrolls too.

Clicks, hovers and scrolls reach the page as real mouse and scroll wheel events, so menus that open on hover and players whose controls appear on mouse movement work as with a mouse. The cursor fades after a few seconds idle. While it's hidden over a playing video, the clickpad goes to the player as keys (for seeking), and a touch or a click brings the cursor back. A press of the clickpad rocks the thumb a little before it clicks, so a click lands where the cursor was just before.

### Sleep Mode

Dims the screen and filters blue light by scaling the display's gamma tables (like Night Shift), so it covers video too. It applies to every display and every app, not just Lazybones. Switch it on in either Settings, or turn on "Show in Control Center" there for a tile. It turns off when Lazybones quits.

### Launch options

Run `Lazybones.app/Contents/MacOS/Lazybones` with any of:

```
--windowed        don't start in full screen
--log             echo the event log to stdout
--no-ext          don't load the extensions (ad blocker, SponsorBlock)
--remote          show the on-screen remote
--ext-debug       report the ad blocker's rulesets
--open <id>       open a service at launch (e.g. youtube)
--open-delay <s>  wait this long (after the ad blocker loads, if it's on) before opening
--debug           show the debug overlay
--page-log        forward everything pages log, not just warnings and errors
--control         take commands from Scripts/ctl.sh (always on in debug builds)
--fresh-settings  start from default settings, without touching the saved ones
--no-hw-remote    leave the Siri Remote to another instance (the on-screen one still works)
```

`--help` lists them.

### Debugging

`make` lists the shortcuts for all of this. The usual loop is `make run`, which builds a debug `Lazybones.app` and runs it windowed with its log in the terminal (`make run ARGS="--open youtube --remote"` for launch options; ^C quits).

| What | How |
|---|---|
| Overlay: app state, the page's DRM, codec and HDR report, console error count, latest log lines | Siri button on the remote, or ⇧⌘D |
| Debug window: the whole log (filter by category, level, text), live app state, each page's reports and a JavaScript console | ⌥⌘I |
| Event log in a terminal | `--log`, or `make logs` for a running app either way (`Scripts/logs.sh -c page`, `Scripts/logs.sh 10m`) |
| Page console | Warnings, errors, uncaught exceptions and rejected promises go to the log under `page`; `--page-log` adds everything else |
| Drive the app from a terminal | `Scripts/ctl.sh` (below) |
| A bug report | Copy Report in the debug window: state, page reports and the log |
| Inspect a page | Safari → Develop → *this Mac* → Lazybones (the web views are inspectable) |
| Raw remote input | `make hud` (`Tools/RemoteHUD`, below) |
| Unit tests | `make test` or `swift test` (the Netflix navigation tests run in a real web view); `make test FILTER=NetflixNavTests` |

The log goes to the unified log under the subsystem `dev.lull.lazybones`, one category per area: `app`, `remote`, `web`, `page`, `tv`, `ext`, `audio`, `control`. Console.app shows it too.

#### Scripts/ctl.sh

Sends commands to a running debug build (or one started with `--control`), so you can work without the remote, script a repro, or let an agent drive it:

```
Scripts/ctl.sh press down down select  remote buttons, one after another ("press home hold" holds)
Scripts/ctl.sh swipe left left         swipes on the touch surface
Scripts/ctl.sh drag 0.2 -0.1           a finger dragged from the touch surface's centre (moves a cursor)
Scripts/ctl.sh turn 180                a finger run around the clickpad's ring (scrolls under a cursor)
Scripts/ctl.sh open netflix
Scripts/ctl.sh eval document.title     JavaScript in the open page (eval @youtube ... for another)
Scripts/ctl.sh state                   what's on screen, overlays, pages, remote, TV, volume
Scripts/ctl.sh log 100                 the last 100 log lines
Scripts/ctl.sh settings | overlay | window | reload
```

`eval` runs as the body of an async function: a bare expression is returned as is, anything longer needs its own `return`. Commands arrive as distributed notifications, which only processes of the same user can post. A second instance next to the one you use every day: `make run ARGS="--fresh-settings --no-hw-remote"`.

## How it works

Three leaf modules know nothing about each other or the app. `Lazybones` is where they meet.

| Module | Responsibility |
|---|---|
| `SiriRemote` | The remote: HID buttons, touch surface, battery. Emits `RemoteEvent`s. |
| `LGTV` | LG webOS TV over the LAN: pairing, volume, mute, power, discovery. |
| `MacSystem` | CoreAudio outputs and per-device volume; network state; screen dimming and tint (Sleep Mode). |
| `Lazybones` | The app, split by feature: |

`Sources/Lazybones/`

| Folder | Responsibility |
|---|---|
| `App/` | Entry point, root view, `AppModel` (decides what a remote command means right now), double-click detection, launch options. |
| `Home/` | The launcher (grid, top shelf, top bar), the zoom out of and back into an icon, and the app switcher. |
| `Services/` | The service model and one folder per built-in service with its site-specific hacks. |
| `Cursor/` | The cursor: `TouchGestures` tells a drag from a turn of the ring, `CursorMotion` moves and snaps it, `CursorController` puts it into the page as mouse and scroll wheel events, `CursorView` draws it. |
| `Web/` | One persistent web view per service: `WebPool`, injected page scripts, the ad blocker extension. |
| `Keyboard/` | On-screen keyboard: state, key layout, the view, and `KeyboardBridge` to the page's field. |
| `ControlCenter/` | The overlay for home, sleep, volume, output and network. |
| `Audio/` | `VolumeRouter` picks what a volume press changes; `VolumeController` applies it and shows the HUD. `SoundSynth` builds the navigation sounds in code and `UISounds` plays them. |
| `Settings/` | `LauncherSettings` (the model), `SettingsStore` (persistence), the Settings window and the remote-driven Settings screen. |
| `Debug/` | The event log and the debug overlay. |
| `Simulator/` | The on-screen remote for development. |

Settings are one JSON blob in UserDefaults. Settings a build can't read are set aside under `launcherSettings.unreadable` instead of being overwritten. The ad blocker is copied to `~/Library/Application Support/Lazybones/Extensions` before loading, because parsing it straight out of the signed app bundle gets the process killed.

## Adding a service

Create `Sources/Lazybones/Services/<Name>/<Name>.swift` with a `ServiceModule` (see `DisneyPlus.swift` for the smallest one), then add it to `ServiceModules.builtIn`. A module can add scripts, CSS and WebKit tweaks that apply to its own web view only. Saved settings pick up new built-ins automatically.

- Its icon comes from a `brand`: the service's official logo (and optionally its symbol alone, for small icons) in `Resources/Brands`, on a plate in its colors. Take the files from the service's brand guidelines or press kit where it has one, otherwise from its own site or repository, and record where each came from in `Resources/Brands/SOURCES.md`. A service without a brand gets an SF Symbol icon, like apps added in Settings.

- A music service sets `pausesInBackground = false` (see `Spotify.swift`) so it keeps playing behind the Home Screen, and a `playPauseScript` that uses its own player, since the default one only toggles the largest video.
- A site uBlock Origin Lite's filters break sets `allowsAdBlocking = false`, and never gets it. Its audio-ad filters redirect media requests to silent clips; Chrome fetches songs another way, but WebKit loads them as media too, so Spotify and SoundCloud fall silent with it on.
- A site the shared remote navigation fits badly can supply its own as `spatialNavScript`, which replaces it under the same setting. `NetflixNavigation.swift` moves through rows, sliders and the details panel like the TV app, and publishes `window.__lazybonesBack` so Back closes what Select opened before it leaves the page.
- A site that only serves its TV interface to TV user agents can opt into one (see `YouTube.swift`, and `BrowserIdentity.swift` for the identity itself).

## Tools

CI (`.github/workflows/ci.yml`) builds, tests and makes the release bundle on every push and pull request.

`Tools/RemoteHUD` (`make hud`) is a standalone window that shows raw HID input from the remote, for working out what a new button sends.
