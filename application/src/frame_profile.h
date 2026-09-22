#pragma once
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Optional local diagnostic. Disabled unless ALLOY3D_FRAME_PROFILE is a CSV path.
// GPU completion records are buffered and written at shutdown; the final
// in-flight frames may be omitted. No disk writes or GPU waits inside a frame.
namespace alloy3d::internal {
using ProfileClock = std::chrono::steady_clock;
inline double profileNow() {
  return std::chrono::duration<double,std::milli>(ProfileClock::now().time_since_epoch()).count();
}
struct FrameProfile {
  unsigned frame=0,width=0,height=0,samples=0,colorDraws=0,shadowDraws=0;
  double interval=0,wait=0,setup=0,update=0,drawable=0,encode=0,gpu=0,driver=0;
  bool rendered=false,completed=false;
};
class FrameProfiler {
  std::string path;
  std::mutex mutex;
  std::vector<FrameProfile> rows;
public:
  unsigned frame=0;
  double last=0;
  explicit FrameProfiler(const char *p):path(p){rows.reserve(8192);}
  void complete(const FrameProfile &row) {
    std::lock_guard<std::mutex> lock(mutex);rows.push_back(row);
  }
  void write() {
    std::lock_guard<std::mutex> lock(mutex);
    std::ofstream out(path);
    out<<"frame,width,height,msaa,interval_ms,inflight_wait_ms,setup_ms,game_ms,drawable_wait_ms,encode_ms,gpu_ms,driver_ms,color_draws,shadow_draws,rendered,completed\n";
    for(const auto &r:rows)out<<r.frame<<','<<r.width<<','<<r.height<<','<<r.samples<<','<<r.interval<<','<<r.wait<<','<<r.setup<<','<<r.update<<','<<r.drawable<<','<<r.encode<<','<<r.gpu<<','<<r.driver<<','<<r.colorDraws<<','<<r.shadowDraws<<','<<r.rendered<<','<<r.completed<<'\n';
  }
};
}
