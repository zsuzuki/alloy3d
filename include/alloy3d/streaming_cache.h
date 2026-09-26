#pragma once
#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <span>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace alloy3d
{
// Optional, single-worker residency cache. Update/Find/Stats are owner-thread only.
// Loader runs on the worker and must return a fully usable immutable resource.
// Desired keys are in priority order, including any hysteresis/retention ring.
// At most maxOutstanding jobs (queued + loading + completed) retain resources.
// Destruction joins the worker: the loader's dependencies must outlive this cache.
template <class T> class StreamingCache
{
public:
  using Key    = uint32_t;
  using Ptr    = std::shared_ptr<T>;
  using Loader = std::function<Ptr(Key)>;
  struct Statistics
  {
    size_t   resident, pending, failed;
    uint64_t loaded, evicted, discarded;
  };

private:
  struct Job
  {
    Key      key;
    uint64_t ticket;
  };
  struct Result
  {
    Job         job;
    Ptr         value;
    std::string error;
  };
  Loader                               loader_;
  const size_t                         maxOutstanding_;
  std::unordered_map<Key, Ptr>         resident_;
  std::unordered_map<Key, uint64_t>    pending_;
  std::unordered_map<Key, std::string> failed_;
  std::mutex                           mutex_;
  std::condition_variable              wake_;
  std::deque<Job>                      jobs_;
  std::deque<Result>                   completed_;
  bool                                 stopping_ = false;
  size_t                               loading_  = 0;
  uint64_t                             ticket_ = 0, loaded_ = 0, evicted_ = 0, discarded_ = 0;
  // Last member so every dependency exists before the worker starts.
  std::thread worker_;
  void        Run()
  {
    for (;;)
    {
      Job job;
      {
        std::unique_lock lock(mutex_);
        wake_.wait(lock, [&] { return stopping_ || !jobs_.empty(); });
        if (stopping_)
          return;
        job = jobs_.front();
        jobs_.pop_front();
        loading_ = 1;
      }
      Result result{job, {}, {}};
      try
      {
        result.value = loader_(job.key);
        if (!result.value)
          result.error = "loader returned null";
      }
      catch (const std::exception &e)
      {
        result.error = e.what();
      }
      catch (...)
      {
        result.error = "unknown loader failure";
      }
      {
        std::lock_guard lock(mutex_);
        loading_ = 0;
        if (stopping_)
          return;
        completed_.push_back(std::move(result));
      }
    }
  }

public:
  explicit StreamingCache(Loader loader, size_t maxOutstanding = 4)
      : loader_(std::move(loader)), maxOutstanding_(std::max(size_t(1), maxOutstanding)),
        worker_([this] { Run(); })
  {
  }
  ~StreamingCache()
  {
    {
      std::lock_guard lock(mutex_);
      stopping_ = true;
      jobs_.clear();
    }
    wake_.notify_one();
    worker_.join();
  }
  StreamingCache(const StreamingCache &)            = delete;
  StreamingCache &operator=(const StreamingCache &) = delete;
  void            Update(std::span<const Key> orderedDesired, size_t maxIntegrations = 1)
  {
    std::unordered_set<Key> desired(orderedDesired.begin(), orderedDesired.end());
    for (auto it = resident_.begin(); it != resident_.end();)
      if (!desired.contains(it->first))
      {
        it = resident_.erase(it);
        ++evicted_;
      }
      else
        ++it;
    std::erase_if(failed_, [&](const auto &entry) { return !desired.contains(entry.first); });
    std::erase_if(pending_, [&](const auto &entry) { return !desired.contains(entry.first); });
    {
      std::lock_guard lock(mutex_);
      auto            current = [&](Job job)
      {
        auto it = pending_.find(job.key);
        return it != pending_.end() && it->second == job.ticket;
      };
      std::erase_if(jobs_, [&](Job job) { return !current(job); });
      size_t integrated = 0;
      for (auto it = completed_.begin(); it != completed_.end();)
      {
        if (!current(it->job))
        {
          it = completed_.erase(it);
          ++discarded_;
        }
        else if (integrated < maxIntegrations)
        {
          const auto key = it->job.key;
          if (it->value)
          {
            resident_[key] = std::move(it->value);
            ++loaded_;
          }
          else
            failed_[key] = std::move(it->error);
          pending_.erase(key);
          it = completed_.erase(it);
          ++integrated;
        }
        else
          ++it;
      }
      for (Key key : orderedDesired)
      {
        if (jobs_.size() + completed_.size() + loading_ >= maxOutstanding_)
          break;
        if (resident_.contains(key) || pending_.contains(key) || failed_.contains(key))
          continue;
        auto ticket = ++ticket_;
        jobs_.push_back({key, ticket});
        pending_[key] = ticket;
      }
      // Reprioritize pending work when the camera changes direction.
      std::stable_sort(jobs_.begin(),
                       jobs_.end(),
                       [&](Job a, Job b)
                       {
                         return std::find(orderedDesired.begin(), orderedDesired.end(), a.key) <
                                std::find(orderedDesired.begin(), orderedDesired.end(), b.key);
                       });
    }
    wake_.notify_one();
  }
  Ptr Find(Key key) const
  {
    auto it = resident_.find(key);
    return it == resident_.end() ? Ptr{} : it->second;
  }
  const auto &Residents() const { return resident_; }
  const auto &Failures() const { return failed_; }
  Statistics  Stats() const
  {
    return {resident_.size(), pending_.size(), failed_.size(), loaded_, evicted_, discarded_};
  }
};
} // namespace alloy3d
