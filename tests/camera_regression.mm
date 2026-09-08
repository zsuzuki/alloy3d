#include "render_harness.h"
#include <limits>
#include <numbers>

using alloy3d::Bounds3D;
using alloy3d::CameraData;
using alloy3d::ProjectionMode;
static void Near(float actual, float expected, const char *message)
{
  Check(std::abs(actual - expected) < 2e-5f, message);
}
static simd_float3 Project(const CameraData &camera, simd_float3 point)
{
  const auto clip = simd_mul(camera.getProjectionMatrix(),
                             simd_mul(camera.getModelViewMatrix(), simd_make_float4(point, 1)));
  return clip.xyz / clip.w;
}
static void Same(const CameraData &a, const CameraData &b)
{
  const auto ap = a.getProjectionMatrix(), bp = b.getProjectionMatrix();
  const auto av = a.getModelViewMatrix(), bv = b.getModelViewMatrix();
  for (int col = 0; col < 4; ++col)
    for (int row = 0; row < 4; ++row)
      Check(ap.columns[col][row] == bp.columns[col][row] &&
                av.columns[col][row] == bv.columns[col][row],
            "rejected operation changed camera matrices");
  Check(a.getAspect() == b.getAspect() && a.getFieldOfView() == b.getFieldOfView() &&
            a.getNearPlane() == b.getNearPlane() && a.getFarPlane() == b.getFarPlane() &&
            a.getOrthographicHeight() == b.getOrthographicHeight() &&
            a.getProjectionMode() == b.getProjectionMode() &&
            simd_length(a.getEyePosition() - b.getEyePosition()) == 0 &&
            simd_length(a.getLookAt() - b.getLookAt()) == 0 &&
            simd_length(a.getUpDirection() - b.getUpDirection()) == 0,
        "rejected operation changed camera settings");
}
static void Rejected(CameraData &camera, const std::function<void()> &operation)
{
  const auto before = camera;
  bool       threw  = false;
  try
  {
    operation();
  }
  catch (const std::invalid_argument &)
  {
    threw = true;
  }
  Check(threw, "invalid camera was accepted");
  Same(camera, before);
}
static void Fits(const CameraData &camera, const Bounds3D &bounds)
{
  for (int corner = 0; corner < 8; ++corner)
  {
    const auto p = Project(camera,
                           simd_make_float3(corner & 1 ? bounds.max.x : bounds.min.x,
                                            corner & 2 ? bounds.max.y : bounds.min.y,
                                            corner & 4 ? bounds.max.z : bounds.min.z));
    Check(std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z) &&
              std::abs(p.x) <= 1.0001f && std::abs(p.y) <= 1.0001f && p.z >= 0 && p.z <= 1,
          "fitted bounds extend outside clip volume");
  }
}
static void CPU()
{
  CameraData camera;
  Check(camera.getProjectionMode() == ProjectionMode::Identity, "default mode changed");
  auto identity = camera.getProjectionMatrix();
  for (int c = 0; c < 4; ++c)
    for (int r = 0; r < 4; ++r)
      Near(identity.columns[c][r], c == r ? 1 : 0, "default identity changed");
  Near(camera.getFieldOfView(), std::numbers::pi_v<float> / 4, "FOV must be radians");
  for (bool ortho : {false, true})
  {
    if (ortho)
      camera.buildOrthographic(4, 2, .1f, 100);
    else
      camera.buildPerspective(std::numbers::pi_v<float> / 2, 2, .1f, 100);
    Near(Project(camera, simd_make_float3(0, 0, -.1f)).z, 0, "near depth must be zero");
    Near(Project(camera, simd_make_float3(0, 0, -100)).z, 1, "far depth must be one");
    Near(Project(camera, simd_make_float3(4, 2, -2)).x, 1, "horizontal edge incorrect");
    Near(Project(camera, simd_make_float3(4, 2, -2)).y, 1, "vertical edge incorrect");
    Check(Project(camera, simd_make_float3(0, 0, -.05f)).z < 0 &&
              Project(camera, simd_make_float3(0, 0, -101)).z > 1,
          "clip volume accepts outside depths");
    camera.setAspectRatio(.5f);
    Near(camera.getNearPlane(), .1f, "resize changed near");
    Near(camera.getFarPlane(), 100, "resize changed far");
    Near(camera.getFieldOfView(), std::numbers::pi_v<float> / 2, "resize changed FOV");
    Check(camera.getProjectionMode() ==
              (ortho ? ProjectionMode::Orthographic : ProjectionMode::Perspective),
          "resize changed mode");
    if (ortho)
      Near(camera.getOrthographicHeight(), 4, "resize changed height");
    Near(Project(camera, simd_make_float3(4, 2, -2)).x,
         4,
         "resize did not change horizontal extent");
    Near(Project(camera, simd_make_float3(4, 2, -2)).y, 1, "resize changed vertical extent");
  }
  for (float bad : {0.f, -1.f, INFINITY, NAN})
  {
    Rejected(camera, [&] { camera.setAspectRatio(bad); });
    Rejected(camera, [&] { camera.buildPerspective(bad, 1, .1, 100); });
    Rejected(camera, [&] { camera.buildOrthographic(bad, 1, .1, 100); });
    Rejected(camera, [&] { camera.buildPerspective(1, 1, bad, 100); });
  }
  Rejected(camera, [&] { camera.buildPerspective(4, 1, .1, 100); });
  Rejected(camera, [&] { camera.buildPerspective(1, 1, 1, 1); });
  Rejected(camera, [&] { camera.buildOrthographic(1, 1, -1, 100); });
  Rejected(camera, [&] { camera.buildOrthographic(1, 1, 0, INFINITY); });
  Rejected(camera, [&] { camera.buildModelView({0, 0, 0}, {0, 0, 0}, {0, 1, 0}); });
  Rejected(camera, [&] { camera.buildModelView({NAN, 0, 0}, {0, 0, 0}, {0, 1, 0}); });
  for (auto up : {simd_make_float3(0, 0, 0), simd_make_float3(0, 1, 0), simd_make_float3(0, -1, 0)})
  {
    camera.buildModelView({0, 2, 0}, {0, 0, 0}, up);
    const auto view = camera.getModelViewMatrix();
    const auto eye  = simd_mul(view, simd_make_float4(0, 2, 0, 1));
    Near(simd_length(eye.xyz), 0, "view does not map eye to origin");
    Near(simd_mul(view, simd_make_float4(0, 0, 0, 1)).z, -2, "target is not on negative Z");
    for (int a = 0; a < 3; ++a)
      for (int b = 0; b < 3; ++b)
        Near(simd_dot(view.columns[a].xyz, view.columns[b].xyz),
             a == b ? 1 : 0,
             "view is not orthonormal");
  }
  Bounds3D bounds{{-4, -2, -8}, {3, 5, 2}}, empty;
  Check(!empty.isValid(), "empty bounds valid");
  empty.include(bounds);
  Check(empty.isValid(), "union failed");
  auto transform = simd_matrix_from_rows(simd_make_float4(0, -2, 0, 4),
                                         simd_make_float4(-3, 0, 0, 5),
                                         simd_make_float4(0, 0, .5, 6),
                                         simd_make_float4(0, 0, 0, 1));
  auto moved     = bounds.transformed(transform);
  Near(simd_length(moved.min - simd_make_float3(-6, -4, 2)), 0, "transformed minimum incorrect");
  Near(simd_length(moved.max - simd_make_float3(8, 17, 7)), 0, "transformed maximum incorrect");
  for (bool ortho : {false, true})
    for (float aspect : {.2f, 1.f, 4.f})
      for (auto box : {bounds, moved, Bounds3D{{0, 0, 0}, {0, 0, 0}}})
      {
        if (ortho)
          camera.buildOrthographic(4, aspect, 0, 100);
        else
          camera.buildPerspective(.9f, aspect, .1, 100);
        camera.buildModelView({8, 5, 12}, {0, 0, 0}, {0, 1, 0});
        const auto direction = simd_normalize(camera.getEyePosition() - camera.getLookAt());
        camera.fitBounds(box, 1);
        Fits(camera, box);
        Near(simd_length(direction - simd_normalize(camera.getEyePosition() - camera.getLookAt())),
             0,
             "fit changed direction");
        Check(camera.getProjectionMode() ==
                  (ortho ? ProjectionMode::Orthographic : ProjectionMode::Perspective),
              "fit changed mode");
      }
  Rejected(camera, [&] { camera.fitBounds({}); });
  Rejected(camera, [&] { camera.fitBounds(bounds, .5); });
  Rejected(camera, [&] { camera.fitBounds(bounds, NAN); });
  CameraData fresh;
  fresh.fitBounds(bounds);
  Fits(fresh, bounds);
  Check(fresh.getProjectionMode() == ProjectionMode::Perspective,
        "identity fit must select perspective");
  std::puts("camera CPU: depth, validation, safe view, resize preservation, bounds and fit passed");
}
static size_t Colored(const Pixels &pixels)
{
  return std::count_if(pixels.begin(), pixels.end(), [](auto p) { return (p & 0xffffff) != 0; });
}
static void GPU(Harness &h, const std::filesystem::path &root, const char *rig)
{
  CameraData camera;
  [h.draw setLightDirection:{0, 0, -1} ambient:1 diffuse:0];
  auto triangle = [&](float depth)
  {
    return Colored(h.Run(camera,
                         [&]
                         {
                           [h.draw drawTriangle:{-.02f, -.02f, -depth}
                                             p1:{.02f, -.02f, -depth}
                                             p2:{0, .02f, -depth}
                                          color:{1, 1, 1, 1}];
                         }));
  };
  camera.buildPerspective(.9f, 1, .1, 10);
  Check(triangle(.15) > 20, "Metal clips visible geometry near the near plane");
  Check(triangle(.05) == 0 && triangle(11) == 0, "Metal near/far clipping failed");
  auto close = triangle(.2), distant = triangle(.4);
  Check(close > distant * 3, "perspective has no depth scaling");
  camera.buildOrthographic(.2, 1, .1, 10);
  Check(triangle(.2) == triangle(2), "orthographic size changes with depth");
  Check(triangle(.05) == 0 && triangle(11) == 0, "orthographic clipping failed");
  for (const char *name : {"normals.glb", "skinned_normals.glb"})
  {
    auto     model = h.Load(root / name);
    Bounds3D bounds;
    Check([model getBounds:&bounds], "model bounds unavailable");
    Near(simd_length(bounds.min - simd_make_float3(-.16f, -.24f, .24f)),
         0,
         "model minimum differs from analytic skin transform");
    Near(simd_length(bounds.max - simd_make_float3(.16f, .24f, .6f)),
         0,
         "model maximum differs from analytic skin transform");
    for (bool ortho : {false, true})
    {
      if (ortho)
        camera.buildOrthographic(2, 1, .1, 100);
      else
        camera.buildPerspective(.9, 1, .1, 100);
      camera.buildModelView({0, 0, 3}, {0, 0, 0}, {0, 1, 0});
      camera.fitBounds(bounds);
      Fits(camera, bounds);
      auto pixels = h.Run(camera,
                          [&]
                          {
                            [h.draw drawModel:model
                                     position:{0, 0, 0}
                                     rotation:{0, 0, 0}
                                        scale:{1, 1, 1}
                                        color:{1, 1, 1, 1}];
                          });
      Check(Colored(pixels) > 100, "fitted model is not visible");
      for (int n = 0; n < 256; ++n)
        Check(!(pixels[n] & 0xffffff) && !(pixels[255 * 256 + n] & 0xffffff) &&
                  !(pixels[n * 256] & 0xffffff) && !(pixels[n * 256 + 255] & 0xffffff),
              "fitted model touches screen edge");
    }
    [model release];
  }
  auto model = h.Load(rig);
  [model setAnimationIndex:0];
  [model setAnimationTime:0];
  Bounds3D initial, animated, copied;
  Check([model getBounds:&initial], "rig bounds unavailable");
  auto clone = [model newInstance];
  [model setAnimationTime:1];
  Check([model getBounds:&animated] && [clone getBounds:&copied], "animated bounds unavailable");
  Check(simd_length(animated.min - initial.min) + simd_length(animated.max - initial.max) > .001,
        "bounds ignore current pose");
  Near(simd_length(copied.min - initial.min) + simd_length(copied.max - initial.max),
       0,
       "clone bounds share mutable pose");
  [model release];
  Check([clone getBounds:&copied], "clone bounds lost after source release");
  [clone release];
  std::puts("camera GPU: clipping, projection, current-pose bounds, clone isolation and fitted "
            "rendering passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      CPU();
      if (argc == 2 && std::strcmp(argv[1], "--cpu") == 0)
        return 0;
      Check(argc == 4, "usage: camera_regression shaders.metallib render-fixtures rig.glb");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
      {
        std::puts("SKIP: no Metal device");
        return 77;
      }
      {
        Harness harness(device, argv[1]);
        GPU(harness, argv[2], argv[3]);
      }
      [device release];
      return 0;
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "FAIL: %s\n", e.what());
      return 1;
    }
  }
}
