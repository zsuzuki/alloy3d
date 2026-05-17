//
// Copyright 2025 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <dispatch/dispatch.h>

//
class SimpleLock
{

  dispatch_semaphore_t sem_ = dispatch_semaphore_create(1);

public:
  ~SimpleLock() { dispatch_release(sem_); }
  void lock() { dispatch_semaphore_wait(sem_, DISPATCH_TIME_FOREVER); }
  void unlock() { dispatch_semaphore_signal(sem_); };
};

//
class SimpleGuard
{
  SimpleLock &lock_;

public:
  SimpleGuard(SimpleLock &lock) : lock_(lock) { lock_.lock(); }
  ~SimpleGuard() { lock_.unlock(); }
};
