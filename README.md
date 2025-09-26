# UI Outlines (Godot 4.5)

Editor-only overlay for the 2D view: draws outlines around **Control** nodes, shows optional name labels, and highlights **selected** nodes on top.

## Install
1. Copy to `res://addons/ui_outlines/`
2. Enable in **Project → Project Settings → Plugins → UI Outlines**

## Use
- In the 2D editor toolbar:
  - **UI Outlines**: toggle outlines
  - **Names**: toggle labels
  - **Labels:** Selected / Leaves / All

## Notes
- Editor only (nothing shows in-game).
- Works with `Control` nodes (Panels, Containers, Labels, etc.).

## Customize
Open `addons/ui_outlines/plugin.gd` and tweak:
- Colors/widths: `_outline_color`, `_outline_color_selected`, `_outline_width`
- Label mode default: `_labels_mode`
- Label behavior: `_avoid_overlap`, `_label_bg`, `_label_text`
