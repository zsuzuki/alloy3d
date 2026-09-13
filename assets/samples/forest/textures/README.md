# Forest textures

These three original surface images were generated for this sample using the built-in OpenAI image generation tool on 2026-09-13. They are AI-generated material illustrations, not photographs or photogrammetry scans. The PNGs are the unmodified generation outputs; no external download or generation service is needed to build or run the sample.

- `ground.png`: damp earth, needles, and fine forest litter; mapped at 1.6 metres per tile.
- `bark.png`: vertical cedar bark; wrapped around trunks, branches, and roots.
- `moss_rock.png`: moss patches and weathered stone; wrapped around boulders.

These are base-color maps only. Scene lighting supplies directional illumination and shadows. The mesh generator embeds these checked-in PNGs in the GLBs with repeating, mipmapped sampling. No normal, roughness, or displacement maps are supplied.

The stream additionally uses `water_surface.png`, generated with the built-in image generation tool.
It includes illustrated water glints and is used as a flowing surface-color and luminance-detail map.
Its provenance and final prompt are in [water-surface-prompt.md](water-surface-prompt.md).

## Generation prompts

### ground.png

Use case: photorealistic-natural. Asset type: seamless square 3D base-color/albedo texture for a forest floor, full frame edge-to-edge. Primary request: photorealistic damp dark umber soil of a Japanese temperate rainforest after rain. Fine granular earth, humus, tiny decomposing cedar needles, delicate rootlets, small muted brown leaf fragments, scattered tiny grit. Subtle sparse dull olive moss flecks, 85 percent soil. Orthographic top-down macro material scan, covers about 1.6m x 1.6m of ground. Entire image in uniform focus. Soft neutral diffuse illumination with no baked directional shadows, no bright highlights, no vignette. Natural muted browns with fine rich detail and modest broad color variation. Seamlessly tileable on all four edges, even density, no obvious repeating landmarks. NO perspective, no horizon, no objects placed on top, no rocks larger than 3cm, no large leaves, no labels, no border, no watermark. Render one texture only, not a material-ball preview or montage. Square 1024x1024.

### bark.png

Use case: photorealistic-natural. Asset type: seamless square 3D albedo texture, edge-to-edge bark surface. Primary request: photorealistic old Japanese cedar bark in a damp forest. Long irregular narrow vertical fibrous ridges, shallow cracks, thin peeling fibers, weathered brown and warm gray bark with extremely sparse subtle olive lichen. No large knots. Orthographic straight-on material scan, covering about .9m wide by .9m high of unwrapped bark, not a photograph of a cylindrical trunk. Vertical grain runs continuously from bottom to top. Flat neutral diffuse illumination: no directional light, no specular shine, no baked ambient shadow gradients, no vignette. Moderate albedo brightness, realistic muted color, excellent fine fibrous detail. Seamlessly tileable on all four edges, no harsh grooves with black shadows. No tree silhouette, no forest background, no perspective, no border, no labels, no watermark. Single texture only, not a material-ball preview. Square 1024x1024.

### moss_rock.png

Use case: photorealistic-natural. Asset type: seamless square 3D base-color/albedo texture for mossy river boulders, edge-to-edge material surface. Primary request: photorealistic damp weathered gray slate/granite covered in irregular patches of lush fine forest moss, approximately 55 percent moss and 45 percent exposed stone. Fine low short moss cushions, miniature leafy moss sprigs visible in dense clumps, dark olive and rich natural green mixed with a few golden green tips. Exposed cool neutral gray stone is rough, pitted, speckled, lightly fractured, subtly damp, never glossy. Orthographic overhead close-up material scan of a continuous surface, about 1m x 1m. No actual boulder silhouette. Uniform neutral diffuse illumination with no strong directional shadows, no reflections, no highlights, no vignette. No giant tufts casting shadows. Seamlessly tileable on all four edges with organic nonperiodic patches and consistent density. No dirt path, no grass blades, no flowers, no background, no text, no border, no watermark. Single texture only, not a material-ball preview. Square 1024x1024.
