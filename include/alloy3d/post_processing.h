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
struct PostProcessing3D
{
  float exposure = 1; // Linear multiplier, finite [0,16].
  ToneMapping3D toneMapping = ToneMapping3D::ACES;
  Bloom3D bloom;
};
} // namespace alloy3d
