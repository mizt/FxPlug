#import "FxMTLDeviceCache.h"

const NSUInteger kMaxCommandQueues = 5;
static NSString *kKey_InUse = @"InUse";
static NSString *kKey_CommandQueue = @"CommandQueue";

static FxMTLDeviceCache *gDeviceCache = nil;

@interface FxMTLDeviceCacheItem : NSObject

@property (readonly) id<MTLDevice> gpuDevice;
@property (readonly) id<MTLRenderPipelineState> pipelineState;
@property (retain) NSMutableArray<NSMutableDictionary*> *commandQueueCache;
@property (readonly) NSLock *commandQueueCacheLock;

-(instancetype)initWithDevice:(id<MTLDevice>)device;
-(id<MTLCommandQueue>)getNextFreeCommandQueue;
-(void)returnCommandQueue:(id<MTLCommandQueue>)commandQueue;
-(BOOL)containsCommandQueue:(id<MTLCommandQueue>)commandQueue;

@end

@implementation FxMTLDeviceCacheItem

-(instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if(self != nil) {
        _gpuDevice = device;
        _commandQueueCache = [[NSMutableArray alloc] initWithCapacity:kMaxCommandQueues];
        for(NSUInteger i=0; (_commandQueueCache!=nil)&&(i<kMaxCommandQueues); i++) {
            NSMutableDictionary *commandDict = [NSMutableDictionary dictionary];
            [commandDict setObject:[NSNumber numberWithBool:NO] forKey:kKey_InUse];
            id<MTLCommandQueue> commandQueue = [_gpuDevice newCommandQueue];
            [commandDict setObject:commandQueue forKey:kKey_CommandQueue];
            [_commandQueueCache addObject:commandDict];
        }
        id<MTLLibrary> defaultLibrary = [_gpuDevice newDefaultLibrary];
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"FxBrightness Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
        NSError *error = nil;
        _pipelineState = [_gpuDevice newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if(error!=nil) NSLog (@"Error generating checkerboard pipeline state: %@", error);
        if(_commandQueueCache!=nil) _commandQueueCacheLock = [[NSLock alloc] init];
        if(!(_gpuDevice&&_commandQueueCache&&_commandQueueCacheLock&&_pipelineState)) {
            self = nil;
        }
    }
    return self;
}

-(void)dealloc {
    _gpuDevice = nil;
    _commandQueueCache = nil;
    _commandQueueCacheLock = nil;
    _pipelineState = nil;
}

-(id<MTLCommandQueue>)getNextFreeCommandQueue {
    id<MTLCommandQueue> result  = nil;
    [_commandQueueCacheLock lock];
    NSUInteger index = 0;
    while((result==nil)&&(index<kMaxCommandQueues)) {
        NSMutableDictionary *nextCommandQueue = [_commandQueueCache objectAtIndex:index];
        NSNumber *inUse = [nextCommandQueue objectForKey:kKey_InUse];
        if(![inUse boolValue]) {
            [nextCommandQueue setObject:[NSNumber numberWithBool:YES] forKey:kKey_InUse];
            result = [nextCommandQueue objectForKey:kKey_CommandQueue];
        }
        index++;
    }
    [_commandQueueCacheLock unlock];
    return result;
}

-(void)returnCommandQueue:(id<MTLCommandQueue>)commandQueue {
    [_commandQueueCacheLock lock];
    BOOL found = false;
    NSUInteger index = 0;
    while((!found)&&(index<kMaxCommandQueues)) {
        NSMutableDictionary *nextCommandQueuDict = [_commandQueueCache objectAtIndex:index];
        id<MTLCommandQueue> nextCommandQueue = [nextCommandQueuDict objectForKey:kKey_CommandQueue];
        if(nextCommandQueue==commandQueue) {
            found = YES;
            [nextCommandQueuDict setObject:[NSNumber numberWithBool:NO] forKey:kKey_InUse];
        }
        index++;
    }
    [_commandQueueCacheLock unlock];
}

-(BOOL)containsCommandQueue:(id<MTLCommandQueue>)commandQueue {
    BOOL found = NO;
    NSUInteger index = 0;
    while((!found)&&(index < kMaxCommandQueues)) {
        NSMutableDictionary *nextCommandQueuDict = [_commandQueueCache objectAtIndex:index];
        id<MTLCommandQueue> nextCommandQueue = [nextCommandQueuDict objectForKey:kKey_CommandQueue];
        if(nextCommandQueue==commandQueue) {
            found = YES;
        }
        index++;
    }
    return found;
}

@end

@implementation FxMTLDeviceCache

+(FxMTLDeviceCache*)deviceCache {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{gDeviceCache = [[FxMTLDeviceCache alloc] init];});
    return gDeviceCache;
}

-(instancetype)init {
    self = [super init];
    if(self!=nil) {
        NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
        deviceCaches = [[NSMutableArray alloc] initWithCapacity:devices.count];
        for (id<MTLDevice> nextDevice in devices) {
            FxMTLDeviceCacheItem *newCacheItem = [[FxMTLDeviceCacheItem alloc] initWithDevice:nextDevice];
            [deviceCaches addObject:newCacheItem];
        }
        devices = nil;
    }
    return self;
}

-(void)dealloc {
    deviceCaches = nil;
}

-(id<MTLDevice>)deviceWithRegistryID:(uint64_t)registryID {
    for(FxMTLDeviceCacheItem* nextCacheItem in deviceCaches) {
        if(nextCacheItem.gpuDevice.registryID==registryID) {
            return nextCacheItem.gpuDevice;
        }
    }
    return nil;
}

-(id<MTLRenderPipelineState>)pipelineStateWithRegistryID:(uint64_t)registryID andFragmentName:(NSString*)fragmentName {
    for(FxMTLDeviceCacheItem* nextCacheItem in deviceCaches) {
        if(nextCacheItem.gpuDevice.registryID == registryID) {
            return nextCacheItem.pipelineState;
        }
    }
    return nil;
}

-(id<MTLCommandQueue>)commandQueueWithRegistryID:(uint64_t)registryID {
    for(FxMTLDeviceCacheItem* nextCacheItem in deviceCaches) {
        if(nextCacheItem.gpuDevice.registryID==registryID) {
            return [nextCacheItem getNextFreeCommandQueue];
        }
    }
    return nil;
}

-(void)returnCommandQueueToCache:(id<MTLCommandQueue>)commandQueue {
    for(FxMTLDeviceCacheItem* nextCacheItem in deviceCaches) {
        if([nextCacheItem containsCommandQueue:commandQueue]) {
            [nextCacheItem returnCommandQueue:commandQueue];
            break;
        }
    }
}

@end
