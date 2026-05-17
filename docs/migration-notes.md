# Alloy3D Migration Notes

This repository is a clean-history restart from the private `metaltest`
prototype. Do not merge or filter the old repository history into this tree.

## Imported

- macOS application launch bridge
- Metal-backed 2D/3D drawing implementation
- camera utilities
- GLB model loading via `cgltf`
- basic GLB animation playback and skinning support
- keyboard and game controller input helpers
- small generated sample GLB assets:
  - `assets/samples/models/animated_bouncer.glb`
  - `assets/samples/models/sample_cube.glb`
  - `assets/samples/models/sample_mdl.glb`

## Deliberately Not Imported

- `sentinel.glb`
- removed `knight*.glb` assets from the old repository history
- old app icon and logo branding
- old `metaltest` README and docs as public-facing documentation
- any Git history from `metaltest`

## Refactor Targets

- Rename public headers into `include/alloy3d`.
- Replace the temporary `application` / `functions` target names with stable
  Alloy3D library targets.
- Split sample apps from reusable library code.
- Decide whether input helpers belong in the public API or remain sample-only.
