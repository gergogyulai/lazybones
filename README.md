<div align="center">
  <br>
  <h1>Lazybones</h1>
  <sub>A tvOS-style launcher for streaming sites, for a Mac plugged into a TV</sub>
  <br>
  <br>
</div>

> **Early.** No releases yet, so build it yourself. Made for a MacBook on a TV with a Siri Remote (USB-C, 2022).

Every streaming site is a persistent web view with an icon on a Home Screen. No browser chrome, no mouse, no keyboard. Built for travelling: a MacBook, a hotel TV and an Apple TV remote.

- 📺 Home Screen, top shelf and app switcher, like tvOS
- 🎮 Supports: Siri Remote or the iOS/iPadOS Apple TV Remote
- 🕹️ Navigation: Arrow keys, focus ring or a custom on-screen cursor. Configurable per app, plus custom navigation for Netflix.
- ⌨️ On-screen keyboard
- 🔊 Volume for the Mac, LG webOS TVs, or the page itself
- 🛡️ uBlock Origin Lite and SponsorBlock, per app
- 🌙 Sleep Mode, a sleep timer, and keeps the Mac awake while open
- 🎛️ Control Center

Built in: YouTube, Netflix, Disney+, Prime Video, HBO Max, Apple TV, SkyShowtime, Paramount+, Crunchyroll, Twitch, Telekom TV GO, Spotify, Apple Music, YouTube Music, SoundCloud, Plex, Jellyfin and Emby. Add any other site in Settings.

## Limitations

- Only the 2022 USB-C Siri Remote and LG webOS TVs. Other TVs fall back to Mac or page volume.
- No HDMI-CEC; Macs can't send it.
- Ad-hoc signed, so it runs on the Mac that built it.
- Playback goes through WebKit, so you get Safari's DRM and codecs.
- Site-specific parts (Netflix navigation, YouTube's TV mode) break when the sites change.

## Build

Requires macOS 15.4+ and Xcode with Swift 6. Rust is optional, for the iPhone remote.

```sh
git clone https://github.com/gergogyulai/lazybones.git
cd lazybones
Scripts/build.sh          # build/Lazybones.app (--debug for a debug build)
open build/Lazybones.app
```

The build downloads uBlock Origin Lite and SponsorBlock. Without them, it still works.

## Launch options

`Lazybones.app/Contents/MacOS/Lazybones --help`

```
--windowed        don't start in full screen
--log             echo the event log to stdout
--no-ext          don't load the extensions
--remote          show the on-screen remote
--open <id>       open a service at launch (e.g. youtube)
--debug           show the debug overlay
--control         take commands from Scripts/ctl.sh (always on in debug builds)
--fresh-settings  start from default settings, without touching the saved ones
--no-hw-remote    leave the Siri Remote to another instance
```

## Credits

The iPhone Remote is implemented through [atv-core](https://github.com/corvofeng/atv-core) by @corvofeng, a Rust port of `fake_atv.py` from [pyatv](https://github.com/postlund/pyatv) by @postlund.
