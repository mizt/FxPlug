#import <Metal/Metal.h>
@class FxMTLDeviceCacheItem;
@interface FxMTLDeviceCache:NSObject {
    NSMutableArray<FxMTLDeviceCacheItem*> *deviceCaches;
}
+(FxMTLDeviceCache*)deviceCache;
-(id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID;
-(id<MTLRenderPipelineState>)pipelineStateWithRegistryID:(uint64_t)registryID andFragmentName:(NSString*)fragmentName;
-(id<MTLCommandQueue>)commandQueueWithRegistryID:(uint64_t)registryID;
-(void)returnCommandQueueToCache:(id<MTLCommandQueue>)commandQueue;
@end
