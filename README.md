# HyprlandConfig

Portable Hyprland desktop configs (Quickshell shell, helper scripts, and —
as they get extracted — Hyprland/Wallust/Wofi templates).

Consumed as a git submodule by
[NixOSConfig](https://github.com/supermarcel10/nixosconfig) at
`modules/desktop_environments/hyprland/configs`, wired in as the
`hyprland-configs` (`git+file`) flake input and exposed to modules as
`paths.hyprland_configs`, e.g. `hyprland_configs + /quickshell-cc/qml`.
The Nix wrappers (`environment.nix`, `quickshell.nix`, `icons.nix`) live in
the parent repo and reference this tree read-only.

## Layout

- `quickshell-cc/qml/` — Quickshell QML sources (`rice-cc` config name).
- `quickshell-cc/bin/` — `rice-*` helper scripts shipped as system packages.

## Conventions

- QML `icon:`/`actionIcon:` values must use Lucide icon names; the parent
  repo's `icons.nix` allow-lists every name the shell may reference and the
  build fails on drift.
- Keep files compositor-portable where possible; NixOS-specific packaging
  stays in the parent repo.
