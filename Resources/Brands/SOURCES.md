# Brand artwork

The built-in services' logos, as each service publishes them, fetched October 2026. Each file is
used unmodified, except that SVGs taken from a page's inline markup got an `xmlns` (and Netflix's
mark a plain gradient id) so they stand alone as files. The logos are their owners' trademarks and
are here only to identify each service on the Home Screen, as their guidelines allow.

Where a service publishes a brand kit, the file comes from it. Otherwise it's the logo the service
serves on its own site.

| File | Source |
|---|---|
| `youtube-logo.pdf` | YouTube brand resources, [brand.youtube/youtube-logo](https://brand.youtube/youtube-logo): `youtube-logo.zip` → `Digital/01 Full Color/yt_logo_fullcolor_white_digital.ai` (a PDF-compatible Illustrator file) |
| `youtube-mark.pdf` | YouTube brand resources, [brand.youtube/youtube-icon](https://brand.youtube/youtube-icon): `youtube-icon.zip` → `Digital/01 Red/yt_icon_red_digital.ai` |
| `netflix-logo.svg` | netflix.com's header logotype (`BrandNetflixLogotype`, served from `occ.a.nflxso.net`). Netflix's brand site, brand.netflix.com, needs a partner login. |
| `netflix-mark.svg` | netflix.com's inline "N" logo (`data-uia="n-logo"`) |
| `disney-logo.png` | disneyplus.com's "Disney+ Logo" image (`disney.images.edge.bamgrid.com`, PNG at full size). Plate colors are sampled from the logo on [press.disneyplus.com/about/logos](https://press.disneyplus.com/about/logos). |
| `prime-logo.png` | primevideo.com's white logo (`m.media-amazon.com/images/G/01/digital/video/acquisition/logo/pv_logo_white.png`). Colors from primevideo.com's stylesheet. |
| `max-logo.svg` | hbomax.com's inline "HBO Max" logo. The same mark is on the [WBD press site](https://press.wbd.com/us/brands/hbo-max), whose blue (#04006C) the plate uses. |
| `spotify-logo.pdf` | Spotify design guidelines, [developer.spotify.com/documentation/design](https://developer.spotify.com/documentation/design): `2024-spotify-full-logo.zip` → `Full_Logo_Green_RGB.pdf` |
| `spotify-mark.pdf` | Same page: `2024-spotify-logo-icon.zip` → `Primary_Logo_Green_RGB.pdf` |
| `plex-logo.svg` | plex.tv's header logo (inline, `aria-label="Plex"`), with `currentColor` set to white |
| `jellyfin-logo.svg` | [jellyfin/jellyfin-ux](https://github.com/jellyfin/jellyfin-ux): `branding/SVG/banner-dark.svg` |
| `jellyfin-mark.svg` | Same repository: `branding/SVG/icon-transparent.svg` |
| `emby-logo.png` | [MediaBrowser/Emby.Resources](https://github.com/MediaBrowser/Emby.Resources): `images/Logos/logowhite.png` |
| `emby-mark.png` | Same repository: `images/Logos/logoicon512.png` |
| `appletv-logo.svg` | tv.apple.com's inline Apple TV logo (in its devices section, `landing-devices__apple-tv-logo`), with `fill="#fff"` added, since the page colors it with CSS |
| `skyshowtime-logo.svg` | skyshowtime.com's inline header logo (`data-testid="skyshowtime-logo"`) |
| `paramount-logo.png` | paramountplus.com's white logo (`/assets/images/intl-landing-page/pplus_marketing_site_logo_white.png`). Colors from the same page. |
| `crunchyroll-logo.svg` | crunchyroll.com's inline header logo (`data-t="crunchyroll-horizontal-svg"`), with `fill="#FF5E00"` added: the orange the page draws it in |
| `twitch-logo.svg` | Twitch brand kit, [brand.twitch.com](https://brand.twitch.com): `Twitch-Brand.zip` → `Twitch Logos/01. Twitch Wordmark/02. Flat Wordmark/04. White/twitch_wordmark_flat_white.svg` |
| `twitch-mark.svg` | Same kit: `Twitch Logos/02. Glitch/04. White/glitch_flat_white.svg` |
| `tvgo-logo.png` | The Telekom TV GO app's icon (Magyar Telekom), from the App Store listing linked on [telekom.hu's TV GO page](https://www.telekom.hu/lakossagi/szolgaltatasok/televizio/telekom-tvgo), at 1024×1024 from Apple's lookup API. The player at player.telekomtvgo.hu only has it as a 32-pixel favicon. |
| `tvgo-mark.svg` | The Telekom "T" from the same telekom.hu page (`Telekom-Logo.svg`), with its navy fill made white, as the T appears on magenta |
| `applemusic-logo.svg` | music.apple.com's inline header logo (`class="logo"`), with `fill="#fff"` added, since the page colors it with CSS |
| `ytmusic-logo.svg` | music.youtube.com's logo for dark backgrounds (`/img/on_platform_logo_dark.svg`, referenced in its page) |
| `ytmusic-mark.svg` | Same site: `/img/on_platform_logo.svg` |
| `soundcloud-logo.svg` | soundcloud.com's inline header logo, with `currentColor` set to the white the page draws it in |

Accent colors are measured from these files: YouTube #FF0033, Netflix #E50914, Spotify #1ED760,
Plex #EBAF00, Jellyfin #AA5CC3, Emby #52B54B, Crunchyroll #FF5E00, YouTube Music #FF0033. The rest
come from the colors each site renders: its buttons, links and backgrounds (Apple TV #0A84FF,
SkyShowtime #795FE3, Paramount+ #0064FF, Twitch #9146FF, TV GO #E20074, Apple Music #FA233B,
SoundCloud #FF5500).
