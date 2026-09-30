> **Early.** Version 0.2, built around one setup: a MacBook on a TV, run with a Siri Remote (USB-C, 2022). There are no releases, so you build it yourself. The site-specific parts (Netflix navigation, YouTube's TV mode) depend on those sites' markup and can break when it changes.

<div align="center">
  <br>
  <h1>Lazybones</h1>
  <sub>A tvOS-style launcher for streaming sites, for a Mac plugged into a TV</sub>
  <br>
  <br>
</div>

Lazybones turns a Mac connected to a TV into something you run from the couch with a Siri Remote. Every streaming site is a persistent web view with an icon on a Home Screen, so switching away from Netflix and back leaves you where you were. There's no browser chrome, no mouse and no keyboard.

- 📺 A Home Screen with a top shelf, an app grid, and a tvOS-style app switcher (swipe up to close an app)
- 🎮 The Siri Remote over USB or Bluetooth: clicks, swipes, long presses, and the volume and power buttons
- 🧭 Remote navigation for any page, plus custom navigation for sites where that isn't enough (Netflix moves through rows, sliders and the details panel like the TV app)
- ⌨️ An on-screen keyboard that follows whichever text field the page has focused
- 🔊 Volume routing: a volume press changes the Mac, an LG TV (and the soundbar on its ARC port), or the page's own media volume, whichever can actually do it
- 🛡️ Ads blocked with uBlock Origin Lite, loaded into the web views
- 🌙 Sleep Mode: dims the screen and filters blue light for every display and every app, video included
- 🎛️ Control Center (hold the TV button): home, sleep, volume, output and network
- 🧪 A debug overlay showing what each page reports about DRM, codecs and HDR, and an on-screen remote so you can develop without the hardware

Built-in apps: YouTube, Netflix, Disney+, Prime Video, HBO Max, Spotify, Plex, Jellyfin and Emby. Two test pages (DRM, ad blocking) sit alongside them for development. You can add any other site in Settings.

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

The build downloads uBlock Origin Lite on first use (`Scripts/fetch-ubol.sh`). If that fails, or you pass `--no-ext` at launch, Lazybones still works, just unblocked. macOS asks for local network access the first time, which is how it finds and talks to the TV.

```sh
swift test                # unit tests
```

Hold the remote's TV button (or ⇧⌘C) for Control Center. ⌥⌘R shows an on-screen remote.

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
| Play/Pause on the Home Screen | Plays or pauses the music left playing (Spotify). |

### Settings

Settings come in two forms. The Settings screen on the Home Screen (or in Control Center) is for the remote: apps shown and their order, layout, Sleep Mode, keyboard, TV. Settings on the Mac (⌘,) has the same plus what needs a keyboard: app names, addresses and colors, and TV pairing by address.

To pair a TV, pick it from the discovered list (or enter its address) and accept the prompt on the screen. Volume steps reach a soundbar on HDMI ARC through the TV. Outputs with no volume control of their own and no TV fall back to the apps' volume.

### Sleep Mode

Dims the screen and filters blue light by scaling the display's gamma tables (like Night Shift), so it covers video too. It applies to every display and every app, not just Lazybones. Switch it on in either Settings, or turn on "Show in Control Center" there for a tile. It turns off when Lazybones quits.

### Launch options

Run `Lazybones.app/Contents/MacOS/Lazybones` with any of:

```
--windowed        don't start in full screen
--log             echo the event log to stdout
--no-ext          don't load the ad blocker
--remote          show the on-screen remote
--ext-debug       report the ad blocker's rulesets
--open <id>       open a service at launch (e.g. youtube)
--open-delay <s>  wait this long (after the ad blocker loads, if it's on) before opening
```

### Debugging

| What | How |
|---|---|
| DRM, codec and HDR report, event log | Siri button on the remote, or ⇧⌘D |
| Event log in a terminal | `--log` |
| Inspect a page | Safari → Develop → *this Mac* → Lazybones (the web views are inspectable) |
| Raw remote input | `Tools/RemoteHUD`, below |
| Unit tests | `swift test` (the Netflix navigation tests run in a real web view) |

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
| `Web/` | One persistent web view per service: `WebPool`, injected page scripts, the ad blocker extension. |
| `Keyboard/` | On-screen keyboard: state, key layout, the view, and `KeyboardBridge` to the page's field. |
| `ControlCenter/` | The overlay for home, sleep, volume, output and network. |
| `Audio/` | `VolumeRouter` picks what a volume press changes; `VolumeController` applies it and shows the HUD. |
| `Settings/` | `LauncherSettings` (the model), `SettingsStore` (persistence), the Settings window and the remote-driven Settings screen. |
| `Debug/` | The event log and the debug overlay. |
| `Simulator/` | The on-screen remote for development. |

Settings are one JSON blob in UserDefaults. Settings a build can't read are set aside under `launcherSettings.unreadable` instead of being overwritten. The ad blocker is copied to `~/Library/Application Support/Lazybones/Extensions` before loading, because parsing it straight out of the signed app bundle gets the process killed.

## Adding a service

Create `Sources/Lazybones/Services/<Name>/<Name>.swift` with a `ServiceModule` (see `DisneyPlus.swift` for the smallest one), then add it to `ServiceModules.builtIn`. A module can add scripts, CSS and WebKit tweaks that apply to its own web view only. Saved settings pick up new built-ins automatically.

- A music service sets `pausesInBackground = false` (see `Spotify.swift`) so it keeps playing behind the Home Screen.
- A site the shared remote navigation fits badly can supply its own as `spatialNavScript`, which replaces it under the same setting. `NetflixNavigation.swift` moves through rows, sliders and the details panel like the TV app, and publishes `window.__lazybonesBack` so Back closes what Select opened before it leaves the page.
- A site that only serves its TV interface to TV user agents can opt into one (see `YouTube.swift`, and `BrowserIdentity.swift` for the identity itself).

## Tools

`Tools/RemoteHUD` is a standalone window that shows raw HID input from the remote, for working out what a new button sends.
