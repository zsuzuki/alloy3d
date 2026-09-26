#include "../samples/open_world/world.h"
#include <chrono>
#include <iostream>
#include <thread>

static void Check(bool pass, const char *message)
{
  if (!pass)
    throw std::runtime_error(message);
}
int main(int argc, char **argv)
{
  try
  {
    Check(argc == 2, "usage: navigation assets");
    open_world::World<int> world(argv[1],
                                 [](const auto &p)
                                 {
                                   if (!std::filesystem::exists(p))
                                     return std::shared_ptr<int>{};
                                   return std::make_shared<int>(1);
                                 });
    for (const auto &b : world.landscape.bridges)
    {
      simd_float3 p{b.x - b.halfSpan - 15, 0, b.z};
      for (int i = 0; i < 200; ++i)
      {
        world.Update(p, .1f);
        if (!world.Stats().pending)
          break;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      }
      Check(!world.Stats().failed, "streaming failed");
      const float target = b.x + b.halfSpan + 15;
      for (int i = 0; i < 160; ++i)
        p = world.Move(p, {1, 0, 0});
      if (p.x < target)
        std::cerr << "bridge stopped at " << p.x - b.x << " relative to center\n";
      Check(p.x >= target, "bridge approach or deck is not walkable");
      p = {b.x, 0, b.z};
      for (int i = 0; i < 20; ++i)
        p = world.Move(p, {0, 0, 1});
      Check(std::abs(p.z - b.z) < 4, "player walked through bridge parapet");
      const auto r = world.landscape.River(b.z + 100);
      p            = {r.x - r.halfWidth * 3, 0, b.z + 100};
      p            = world.Move(p, {r.halfWidth * 6, 0, 0});
      Check(p.x < r.x - r.halfWidth, "fast movement tunneled through river");
    }
    // The complete scenic route crosses both bridges and stays on dry walkable ground.
    for (size_t i = 1; i < world.landscape.route.size(); ++i)
    {
      auto  a = world.landscape.route[i - 1], b = world.landscape.route[i];
      int   steps = int(std::ceil(simd_length(b - a)));
      auto  prev  = a;
      float h     = world.landscape.WalkHeight(a.x, a.y);
      for (int j = 1; j <= steps; ++j)
      {
        auto  p    = a + (b - a) * (float(j) / steps);
        float next = world.landscape.WalkHeight(p.x, p.y);
        Check(world.landscape.Dry(p.x, p.y), "scenic trail crosses water outside a bridge");
        Check(std::abs(next - h) < simd_length(p - prev) * .9f + .05f,
              "scenic trail exceeds walking slope");
        prev = p;
        h    = next;
      }
    }
    auto p = world.landscape.Spawn();
    world.Update(p, .1f);
    for (int i = 0; i < 100; ++i)
    {
      world.Update(p, .1f);
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    const auto &b = world.landscape.bridges.front();
    Check(!world.ClearObjects(b.x - 240, b.z + 22), "village house collision missing");
    Check(world.ClearObjects(b.x - 240, b.z), "village main road is blocked");
    std::cout
        << "navigation: both bridges, rails, river, scenic trail and house collision passed\n";
    return 0;
  }
  catch (const std::exception &e)
  {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
