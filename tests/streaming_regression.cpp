#include <alloy3d/streaming_cache.h>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <stdexcept>

using Cache = alloy3d::StreamingCache<int>;
void Check(bool ok, const char *message)
{
  if (!ok)
    throw std::runtime_error(message);
}
template <class F> void Until(F ready)
{
  const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  while (!ready())
  {
    if (std::chrono::steady_clock::now() > end)
      throw std::runtime_error("streaming test timed out");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
int main()
{
  try
  {
    std::atomic<int> alive = 0, calls = 0;
    auto             load = [&](unsigned key)
    {
      ++calls;
      if (key == 999)
        throw std::runtime_error("expected fixture failure");
      ++alive;
      return Cache::Ptr(new int(key),
                        [&](int *p)
                        {
                          delete p;
                          --alive;
                        });
    };
    {
      Cache                 cache(load, 2);
      std::vector<unsigned> desired{1, 2, 3, 4, 1};
      Until(
          [&]
          {
            cache.Update(desired, 1);
            Check(cache.Stats().pending <= 2, "unbounded requests");
            return cache.Stats().resident == 4;
          });
      Check(calls == 4, "duplicate asset loaded");
      auto first = cache.Find(1);
      cache.Update(desired);
      Check(cache.Find(1) == first, "resident identity changed");
      first.reset();
      std::vector<unsigned> away{8, 9};
      Until(
          [&]
          {
            cache.Update(away);
            return cache.Stats().resident == 2;
          });
      Check(cache.Stats().evicted == 4, "old cells not evicted");
      Check(alive == 2, "evicted cells retained");
      std::vector<unsigned> fail{999};
      Until(
          [&]
          {
            cache.Update(fail);
            return cache.Stats().failed == 1;
          });
      int failedCalls = calls;
      for (int i = 0; i < 10; ++i)
        cache.Update(fail);
      Check(calls == failedCalls, "failure retries every frame");
      cache.Update({});
      Check(cache.Stats().resident == 0 && cache.Stats().failed == 0,
            "clear did not release entries");
    }
    Check(alive == 0, "destruction retained resources");
    // Hold a load across cancellation and re-request of the same key. The old
    // completion must not replace a newer request or bypass integration limits.
    std::mutex              mutex;
    std::condition_variable cv;
    bool                    started = false, release = false;
    std::atomic<unsigned>   sequence = 0;
    {
      Cache cache(
          [&](unsigned)
          {
            unsigned n = ++sequence;
            if (n == 1)
            {
              std::unique_lock lock(mutex);
              started = true;
              cv.notify_one();
              cv.wait(lock, [&] { return release; });
            }
            return std::make_shared<int>(n);
          },
          2);
      std::vector<unsigned> key{42};
      cache.Update(key);
      {
        std::unique_lock lock(mutex);
        Check(cv.wait_for(lock, std::chrono::seconds(2), [&] { return started; }),
              "worker did not start");
      }
      cache.Update({});
      cache.Update(key, 0);
      {
        std::lock_guard lock(mutex);
        release = true;
      }
      cv.notify_one();
      Until(
          [&]
          {
            cache.Update(key, 0);
            return sequence == 2;
          });
      Check(!cache.Find(42), "zero integration budget ignored");
      Until(
          [&]
          {
            cache.Update(key, 1);
            return bool(cache.Find(42));
          });
      Check(*cache.Find(42) == 2, "stale load was published");
      Check(cache.Stats().discarded == 1, "stale load not accounted for");
    }
    std::puts("streaming: bounded requests, sharing, eviction, failures, stale completion and "
              "shutdown passed");
    return 0;
  }
  catch (const std::exception &e)
  {
    std::fprintf(stderr, "FAIL: %s\n", e.what());
    return 1;
  }
}
