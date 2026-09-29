# Lull

A tvOS-style launcher for streaming sites on a Mac connected to a TV, driven by the Siri Remote.
Each app is a persistent web view with a Home Screen entry; Lull adds remote navigation, an
on-screen keyboard, volume routing (Mac, LG TV or the pages themselves) and an ad blocker
(uBlock Origin Lite).

Requires macOS 15.4 and Swift 6.

## Build and run

    Scripts/build.sh          # release build to build/Lull.app (--debug for a debug build)
    open build/Lull.app

The build downloads uBlock Origin Lite on first use (`Scripts/fetch-ubol.sh`). Without it Lull
still works, just unblocked.

    swift test                # unit tests

Hold the remote's TV button (or ⇧⌘C) for Control Center. ⌥⌘R shows an on-screen remote, so you can
develop without the hardware.

Controls, on the remote or the keyboard equivalents in the Lull menu:

| Do this | To get |
| --- | --- |
| Click the TV button | Home. Already Home: back to the first app. |
| Double-click the TV button (⇧⌘A) | The app switcher: select to resume, swipe up to close an app. |
| Hold the TV button, or Power (⇧⌘C) | Control Center. |
| Back | The page before, else Home. Sites with a TV interface get it first (see `WebPool.back`). |
| Up from the first row of apps | The Home Screen's Settings button (⌥⌘, from anywhere). |
| Play/Pause on the Home Screen | Plays or pauses the music left playing (Spotify). |

Settings come in two forms. The Settings screen on the Home Screen (or in Control Center) is for the
remote: apps shown and their order, layout, Sleep Mode, keyboard, TV. Settings on the Mac (⌘,) has
the same plus what needs a keyboard: app names, addresses and colors, and TV pairing by address.

**Sleep Mode** dims the screen and filters blue light by scaling the display's gamma tables (like
Night Shift), so it covers video too. Switch it on in either Settings, or turn on "Show in Control
Center" there for a tile. It turns off when Lull quits.

### Launch options

Run `Lull.app/Contents/MacOS/Lull` with any of:

    --windowed        don't start in full screen
    --log             echo the event log to stdout
    --no-ext          don't load the ad blocker
    --remote          show the on-screen remote
    --ext-debug       report the ad blocker's rulesets
    --open <id>       open a service at launch (e.g. youtube)
    --open-delay <s>  wait this long (after the ad blocker loads, if it's on) before opening

The debug overlay (Siri button, or ⇧⌘D) shows what each page reports about DRM, codecs and HDR.

## Layout

Three leaf modules know nothing about each other or the app. `Lull` is where they meet.

| Module | Responsibility |
| --- | --- |
| `SiriRemote` | The remote: HID buttons, touch surface, battery. Emits `RemoteEvent`s. |
| `LGTV` | LG webOS TV over the LAN: pairing, volume, mute, power, discovery. |
| `MacSystem` | CoreAudio outputs and per-device volume; network state; screen dimming and tint (Sleep Mode). |
| `Lull` | The app, split by feature: |

`Sources/Lull/`

| Folder | Responsibility |
| --- | --- |
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

## Adding a service

Create `Sources/Lull/Services/<Name>/<Name>.swift` with a `ServiceModule` (see `Netflix.swift` for the
smallest one), then add it to `ServiceModules.builtIn`. A module can add scripts, CSS and WebKit
tweaks that apply to its own web view only. Saved settings pick up new built-ins automatically.
A music service sets `pausesInBackground = false` (see `Spotify.swift`) so it keeps playing behind
the Home Screen.

## Tools

`Tools/RemoteHUD` is a standalone window that shows raw HID input from the remote, for working out
what a new button sends.
