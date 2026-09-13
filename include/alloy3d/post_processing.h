#pragma once
namespace alloy3d
{
enum class ToneMapping3D { None, Reinhard, ACES };
struct Bloom3D
{
  float strength = 0; // [0,4], zero disables without allocating blur targets.
  float threshold = 1; // Scene-linear brightness, before exposure, [0,64].
  float radius = 4; // Half-resolution pixels, [1,32].
};
struct VolumetricLight3D
{
  float strength = 0; // [0,4], requires sceneEffects; zero allocates no volume target
  float density = .03f; // [0,1], extinction per world unit
  float baseHeight = 0;
  float falloff = .2f; // [0,10], exponential world-height density falloff
  float maxDistance = 50; // (0,1000]
  float anisotropy = .35f; // [-.9,.9], forward scattering
  unsigned steps = 32; // [8,64]
};
struct PostProcessing3D
{
  float exposure = 1; // Linear multiplier, finite [0,16].
  ToneMapping3D toneMapping = ToneMapping3D::ACES;
  Bloom3D bloom;
  VolumetricLight3D volumetric;
};
} // namespace alloy3d
