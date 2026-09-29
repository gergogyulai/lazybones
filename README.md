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
develop without the hardware. Settings (⌘,) has apps, layout, TV pairing and the keyboard.

### Launch options

Run `Lull.app/Contents/MacOS/Lull` with any of:

    --windowed        don't start in full screen
    --log             echo the event log to stdout
    --no-ext          don't load the ad blocker
    --remote          show the on-screen remote
    --ext-debug       report the ad blocker's rulesets
    --open <id>       open a service at launch (e.g. youtube)
    --open-delay <s>  wait this long after the ad blocker loads before opening

The debug overlay (Siri button, or ⇧⌘D) shows what each page reports about DRM, codecs and HDR.

## Layout

Three leaf modules know nothing about each other or the app. `Lull` is where they meet.

| Module | Responsibility |
| --- | --- |
| `SiriRemote` | The remote: HID buttons, touch surface, battery. Emits `RemoteEvent`s. |
| `LGTV` | LG webOS TV over the LAN: pairing, volume, mute, power, discovery. |
| `MacSystem` | CoreAudio outputs and per-device volume; network state. |
| `Lull` | The app, split by feature: |

`Sources/Lull/`

| Folder | Responsibility |
| --- | --- |
| `App/` | Entry point, root view, `AppModel` (decides what a remote command means right now), launch options. |
| `Home/` | The launcher grid and top shelf. |
| `Services/` | The service model and one folder per built-in service with its site-specific hacks. |
| `Web/` | One persistent web view per service: `WebPool`, injected page scripts, the ad blocker extension. |
| `Keyboard/` | On-screen keyboard: state, key layout, the view, and `KeyboardBridge` to the page's field. |
| `ControlCenter/` | The overlay for home, sleep, volume, output and network. |
| `Audio/` | `VolumeRouter` picks what a volume press changes; `VolumeController` applies it and shows the HUD. |
| `Settings/` | `LauncherSettings` (the model), `SettingsStore` (persistence) and the Settings window. |
| `Debug/` | The event log and the debug overlay. |
| `Simulator/` | The on-screen remote for development. |

## Adding a service

Create `Sources/Lull/Services/<Name>/<Name>.swift` with a `ServiceModule` (see `Netflix.swift` for the
smallest one), then add it to `ServiceModules.builtIn`. A module can add scripts, CSS and WebKit
tweaks that apply to its own web view only. Saved settings pick up new built-ins automatically.

## Tools

`Tools/RemoteHUD` is a standalone window that shows raw HID input from the remote, for working out
what a new button sends.
