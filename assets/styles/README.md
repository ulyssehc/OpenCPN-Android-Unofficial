# Replacement style icons

`android/androidUTIL.cpp` loads four PNGs from `<SharedDataDir>/styles/` and
feeds them into Qt stylesheets:

| File | Used for |
|---|---|
| `chek_empty.png` / `chek_full.png` | `QCheckBox::indicator`, unchecked / checked |
| `tabbar_button_left.png` / `tabbar_button_right.png` | `QTabBar QToolButton` left / right arrow |

**They are published nowhere.** Not in `OpenCPN/OpenCPN` (`data/styles/` holds
only `qtstylesheet.qss`), not in `bdbcat/OpenCPN-Android`, not in
`OCPNAndroidCommon`, not in `OCPNAndroidCoreBuildSupport`. The upstream
maintainer evidently has them locally. Without them the settings dialog shows
an empty box where each tab-scroll arrow and every checkbox should be, and the
only trace is four `can't open file` lines in `opencpn.log`.

These are therefore **our own drawings**, not upstream artwork: plain blue
triangles and a rounded checkbox with a tick, 128x128 RGBA. The app rescales
them to `30 x density` (checkbox) and `50 x density` (arrows), so the source is
deliberately larger than needed.

Regenerate or restyle them with any image tool; only the file names, square
aspect and transparency matter.
