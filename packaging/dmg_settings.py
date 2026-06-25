"""dmgbuild settings for the Hangar release DMG.

Produces a styled drag-to-Applications disk image *without* driving Finder /
AppleScript (so it's reliable on CI). Used by .github/workflows/release.yml:

    DMG_APP="path/to/Hangar.app" dmgbuild -s packaging/dmg_settings.py "Hangar" Hangar.dmg
"""
import os
import os.path

# Path to the built .app — passed in via the environment so this file works
# both locally and in CI (dmgbuild execs this file without defining __file__).
app = os.environ["DMG_APP"]
appname = os.path.basename(app)

# Compressed, read-only image.
format = "UDZO"

# Branded background (arrow app -> Applications, drop-zone outline). HiDPI TIFF.
# Path comes from the environment; omit it to fall back to a plain window.
background = os.environ.get("DMG_BACKGROUND") or None

# Window contents: the app plus an "Applications" symlink to drag onto.
files = [app]
symlinks = {"Applications": "/Applications"}

# Layout: app icon on the left, Applications folder on the right.
icon_locations = {
    appname: (150, 185),
    "Applications": (450, 185),
}
window_rect = ((200, 120), (600, 400))
icon_size = 128
text_size = 13

# Clean, fixed-looking window: hide all the chrome so there's nothing to fiddle
# with. (macOS has no real "non-resizable" flag for Finder/DMG windows, but with
# no toolbar/status bar and an anchored background it reads as a fixed window.)
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
