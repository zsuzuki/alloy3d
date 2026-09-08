#pragma once
#import <Foundation/Foundation.h>

// Byte-bounded LRU with a secondary 512-entry cap. Values returned by lookup
// are borrowed; drawing requests retain them independently of cache residency.
@interface MemoryCache : NSObject
- (instancetype)initWithLimit:(NSUInteger)limit;
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key cost:(NSUInteger)cost;
- (void)setLimit:(NSUInteger)limit;
- (void)removeAllObjects;
- (NSUInteger)bytes;
- (NSUInteger)count;
@end
