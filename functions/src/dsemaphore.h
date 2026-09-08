//
// Copyright 2025 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <os/lock.h>

//
class SimpleLock
{

  os_unfair_lock lock_ = OS_UNFAIR_LOCK_INIT;

public:
  SimpleLock() = default;
  SimpleLock(const SimpleLock &) = delete;
  SimpleLock &operator=(const SimpleLock &) = delete;
  void lock() { os_unfair_lock_lock(&lock_); }
  void unlock() { os_unfair_lock_unlock(&lock_); }
};

//
class SimpleGuard
{
  SimpleLock &lock_;

public:
  SimpleGuard(SimpleLock &lock) : lock_(lock) { lock_.lock(); }
  SimpleGuard(const SimpleGuard &) = delete;
  SimpleGuard &operator=(const SimpleGuard &) = delete;
  ~SimpleGuard() { lock_.unlock(); }
};
