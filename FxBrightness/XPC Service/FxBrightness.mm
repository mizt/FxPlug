#import <simd/simd.h>
#import "FxMTLDeviceCache.h"
#import "FxBrightness.h"
#import "FxBrightnessShaderTypes.h"

struct BrightnessParams {
    float brightness;
};

@implementation FxBrightness

-(nullable instancetype)initWithAPIManager:(id<PROAPIAccessing>)newApiManager {
    self = [super init];
    if(self!=nil) _apiManager = newApiManager;
    return self;
}

-(BOOL)addParametersWithError:(NSError **_Nullable)error {
    id<FxParameterCreationAPI_v5> paramAPI = [_apiManager apiForProtocol:@protocol(FxParameterCreationAPI_v5)];
    if(paramAPI==nil) {
        if(error!=nil) {
            NSString *description = [NSString stringWithFormat:@"Unable to get the FxParameterCreationAPI_v5 in %s",__func__];
            *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_APIUnavailable userInfo:@{NSLocalizedDescriptionKey:description}];
        }
        return NO;
    }
    [paramAPI addFloatSliderWithName:@"Brightness" parameterID:1 defaultValue:1.0 parameterMin:0.0 parameterMax:100.0 sliderMin:0.0 sliderMax:5.0 delta:0.1 parameterFlags:kFxParameterFlag_DEFAULT];
    return YES;
}

- (BOOL)properties:(NSDictionary *_Nonnull *)properties error:(NSError * _Nullable *)error {
    *properties =  @{
        kFxPropertyKey_MayRemapTime:@NO,
        kFxPropertyKey_PixelTransformSupport:[NSNumber numberWithInt:kFxPixelTransform_Full],
        kFxPropertyKey_VariesWhenParamsAreStatic:@NO,
        kFxPropertyKey_ChangesOutputSize:@NO
    };
    return YES;
}

-(BOOL)pluginState:(NSData *_Nonnull *)pluginState atTime:(CMTime)renderTime quality:(FxQuality)qualityLevel error:(NSError * _Nullable *)error {
    id<FxParameterRetrievalAPI_v6> paramAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if(paramAPI==nil) {
        NSString *description =
        [NSString stringWithFormat:@"Unable to get the FxParameterRetrievalAPI_v6 in %s", __func__];
        if(error!=nil) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_APIUnavailable userInfo:@{NSLocalizedDescriptionKey:description}];
        }
        return NO;
    }
    
    BrightnessParams params;
    double brightness = 0.0;
    [paramAPI getFloatValue:&brightness fromParameter:1 atTime:renderTime];
    params.brightness = (float)brightness;
    
    NSMutableData *paramData = [NSMutableData data];
    [paramData appendBytes:&params length:sizeof(params)];
    
    *pluginState = paramData;
    
    return YES;
}

-(BOOL)destinationImageRect:(FxRect *)destinationImageRect sourceImages:(NSArray<FxImageTile *> *)sourceImages destinationImage:(FxImageTile*)destinationImage pluginState:(NSData *)pluginState atTime:(CMTime)renderTime error:(NSError * _Nullable *)outError {
    *destinationImageRect = sourceImages[0].imagePixelBounds;
    return YES;
}

-(BOOL)sourceTileRect:(FxRect *)sourceTileRect sourceImageIndex:(NSUInteger)sourceImageIndex sourceImages:(NSArray<FxImageTile *> *)sourceImages destinationTileRect:(FxRect)destinationTileRect destinationImage:(FxImageTile *)destinationImage pluginState:(NSData *)pluginState atTime:(CMTime)renderTime error:(NSError * _Nullable *)outError {
    *sourceTileRect = destinationTileRect;
    return YES;
}

-(BOOL)renderDestinationImage:(FxImageTile *)destinationImage sourceImages:(NSArray<FxImageTile *> *)sourceImages pluginState:(NSData *)pluginState atTime:(CMTime)renderTime error:(NSError *_Nullable *)outError {
    if(pluginState==nil) {
        if(outError!= nil) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter userInfo:@{NSLocalizedDescriptionKey:@"Plugin State is nil"}];
        }
        return NO;
    }
    
    FxMTLDeviceCache *deviceCache = [FxMTLDeviceCache deviceCache];
    id<MTLCommandQueue> commandQueue = [deviceCache commandQueueWithRegistryID:destinationImage.deviceRegistryID];
    if(commandQueue==nil) {
        NSLog(@"Unable to get command queue! May need to increase cache size!");
        return NO;
    }
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"FxBrightness Command Buffer";
    [commandBuffer enqueue];
    
    id<MTLTexture> inputTexture = [sourceImages[0] metalTextureForDevice:[deviceCache deviceWithRegistryID:sourceImages[0].deviceRegistryID]];
    id<MTLTexture> outputTexture = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];
    
    MTLRenderPassColorAttachmentDescriptor* colorAttachmentDescriptor = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
    colorAttachmentDescriptor.texture = outputTexture;
    colorAttachmentDescriptor.clearColor = MTLClearColorMake(0.0,0.5,1.0,1.0);
    colorAttachmentDescriptor.loadAction = MTLLoadActionClear;
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0] = colorAttachmentDescriptor;
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    float outputWidth = (float)(destinationImage.tilePixelBounds.right-destinationImage.tilePixelBounds.left);
    float outputHeight = (float)(destinationImage.tilePixelBounds.top-destinationImage.tilePixelBounds.bottom);
   
    Vertex2D vertices[4]  = {
        {{ outputWidth*0.5f,-outputHeight*0.5f},{1.0,1.0}},
        {{-outputWidth*0.5f,-outputHeight*0.5f},{0.0,1.0}},
        {{ outputWidth*0.5f, outputHeight*0.5f},{1.0,0.0}},
        {{-outputWidth*0.5f, outputHeight*0.5f},{0.0,0.0}}
    };
    
    MTLViewport viewport = {0,0,outputWidth,outputHeight,-1.0,1.0};
    [commandEncoder setViewport:viewport];
    
    id<MTLRenderPipelineState>  pipelineState = [deviceCache pipelineStateWithRegistryID:destinationImage.deviceRegistryID andFragmentName:@"FxBrightness"];
    [commandEncoder setRenderPipelineState:pipelineState];
    [commandEncoder setVertexBytes:vertices length:sizeof(vertices) atIndex:BVI_Vertices];
    [commandEncoder setFragmentTexture:inputTexture atIndex:BTI_InputImage];
    
    simd_uint2 viewportSize = {(unsigned int)(outputWidth),(unsigned int)(outputHeight)};
    [commandEncoder setVertexBytes:&viewportSize length:sizeof(viewportSize) atIndex:BVI_ViewportSize];
    
    const BrightnessParams *unpackedState = (BrightnessParams *)[pluginState bytes];

    float fragmentBrightness = unpackedState->brightness;
    [commandEncoder setFragmentBytes:&fragmentBrightness length:sizeof(fragmentBrightness) atIndex:0];
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [commandEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
    
    colorAttachmentDescriptor = nil;
    [deviceCache returnCommandQueueToCache:commandQueue];
    inputTexture = nil;
    
    return YES;
}

@end
