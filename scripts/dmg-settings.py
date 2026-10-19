# dmgbuild settings for Harvestbeam's disk image; scripts/make-dmg.sh passes
# app= and background= with -D. Icon positions match the background drawn by
# scripts/make-dmg-background.swift.
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
# 800pt wide: Finder on macOS 27 won't open a window much narrower, and the
# design is centered on that width. The height leaves ~90pt over the 440pt
# design for the title bar plus the path and status bars, which Finder shows
# if the user keeps them on. With them off, the background carries on below.
window_rect = ((160, 120), (800, 530))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (260, 228),
    "Applications": (540, 228),
}
format = "UDZO"
