# Original forest assets

Geometry is generated exclusively for Alloy3D by `tools/generate_forest_assets.py` (Python standard library).
These assets, including the PNGs and embedded images in the GLBs, are provided under
the repository's [MIT License](../../../LICENSE), to the extent the maintainers hold
applicable rights. AI-generated images may not carry copyright in every jurisdiction;
this notice does not assert exclusive rights in them. No third-party model or marketplace asset is included.
Ground, bark, and mossy stone use three AI-generated albedo images created for this sample,
checked in under [textures](textures/README.md) with the generation prompts and provenance.

The 47 GLBs contain terrain, grass, fern, rock, light shaft, floating mote, water droplet and stream assets,
plus three recursively generated tree variants. Each tree has a trunk/root mesh, crown wood,
and foliage; the latter two also have matching distant meshes.
Trees have four branching orders, curved tapered limbs, and leaves attached to the finer shoots.
The high-detail trees contain 14,713–14,919 leaves and 189,380–192,036 triangles each;
the distant versions contain 47,560–48,200 triangles. These counts include the trunk.
Twenty-four additional GLBs are two-triangle MASK billboards of the crowns, baked from
these same meshes at eight azimuth angles per tree. See [billboards](billboards/README.md).
The stream uses an AI-generated [water surface texture](textures/water-surface-prompt.md).
The surface PNGs are embedded in their GLBs with repeating, mipmapped sampling.
`--check` verifies that the checked-in binaries match the deterministic generator and source images.
Run `tools/generate_forest_billboards.py --check` separately to verify billboard GLBs and source hashes.

See [the forest sample guide](../../../docs/forest-sample-ja.md) for controls, rendering approximations,
and the Metal preview probe.
