#pragma once
namespace alloy3d
{
enum class ToneMapping3D { None, Reinhard, ACES };
struct PostProcessing3D
{
  float exposure = 1; // Linear multiplier, finite [0,16].
  ToneMapping3D toneMapping = ToneMapping3D::ACES;
};
} // namespace alloy3d
