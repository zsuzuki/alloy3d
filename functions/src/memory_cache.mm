#import <alloy3d/metal/memory_cache.h>

@interface MemoryCacheEntry : NSObject
{
@public
  id                value;
  NSString         *key;
  NSUInteger        cost;
  MemoryCacheEntry *previous;
  MemoryCacheEntry *next;
}
@end

@implementation MemoryCacheEntry
- (void)dealloc
{
  [value release];
  [key release];
  [super dealloc];
}
@end

@implementation MemoryCache
{
  NSMutableDictionary *entries_;
  MemoryCacheEntry    *oldest_;
  MemoryCacheEntry    *newest_;
  NSUInteger           bytes_;
  NSUInteger           limit_;
}

- (instancetype)initWithLimit:(NSUInteger)limit
{
  self = [super init];
  if (self)
  {
    entries_ = [[NSMutableDictionary alloc] init];
    limit_   = limit;
  }
  return self;
}

- (void)unlink:(MemoryCacheEntry *)entry
{
  if (entry->previous)
    entry->previous->next = entry->next;
  else
    oldest_ = entry->next;
  if (entry->next)
    entry->next->previous = entry->previous;
  else
    newest_ = entry->previous;
  entry->previous = nil;
  entry->next     = nil;
}

- (void)append:(MemoryCacheEntry *)entry
{
  entry->previous = newest_;
  if (newest_)
    newest_->next = entry;
  else
    oldest_ = entry;
  newest_ = entry;
}

- (void)evict:(MemoryCacheEntry *)entry
{
  [self unlink:entry];
  bytes_ -= entry->cost;
  // The dictionary owns entry. Do not access entry after removing it.
  [entries_ removeObjectForKey:entry->key];
}

- (id)objectForKey:(NSString *)key
{
  MemoryCacheEntry *entry = [entries_ objectForKey:key];
  if (!entry)
    return nil;
  [self unlink:entry];
  [self append:entry];
  return entry->value;
}

- (void)setObject:(id)object forKey:(NSString *)key cost:(NSUInteger)cost
{
  if (!object || !key)
    return;
  // Retain before eviction: callers may replace a cache-owned value with itself.
  auto entry   = [[MemoryCacheEntry alloc] init];
  entry->value = [object retain];
  entry->key   = [key copy];
  entry->cost  = cost;
  if (MemoryCacheEntry *old = [entries_ objectForKey:key])
    [self evict:old];
  if (limit_ == 0 || cost > limit_)
  {
    [entry release];
    return;
  }
  while (oldest_ && (bytes_ > limit_ - cost || entries_.count >= 512))
    [self evict:oldest_];
  [entries_ setObject:entry forKey:entry->key];
  [self append:entry];
  bytes_ += cost;
  [entry release];
}

- (void)setLimit:(NSUInteger)limit
{
  limit_ = limit;
  while (oldest_ && (bytes_ > limit_ || limit_ == 0))
    [self evict:oldest_];
}

- (void)removeAllObjects
{
  oldest_ = newest_ = nil;
  bytes_            = 0;
  [entries_ removeAllObjects];
}
- (NSUInteger)bytes
{
  return bytes_;
}
- (NSUInteger)count
{
  return entries_.count;
}
- (void)dealloc
{
  [entries_ release];
  [super dealloc];
}
@end
