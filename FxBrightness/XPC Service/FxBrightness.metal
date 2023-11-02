#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#include "FxBrightnessShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} RasterizerData;

vertex RasterizerData vertexShader(uint vertexID[[vertex_id]], constant Vertex2D *vertexArray[[buffer(BVI_Vertices)]], constant vector_uint2 *viewportSizePointer[[buffer(BVI_ViewportSize)]]) {
    RasterizerData out;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);
    out.clipSpacePosition.xy = pixelSpacePosition/(viewportSize*0.5);
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]],texture2d<half> colorTexture [[texture(BTI_InputImage)]], constant float *brightness[[buffer(BFI_Brightness)]]) {
    constexpr sampler textureSampler(mag_filter::linear,min_filter::linear);
    half4 colorSample = colorTexture.sample(textureSampler,in.textureCoordinate);
    const half hBrightness = (half)(*brightness);
    colorSample.rgb = colorSample.rgb*hBrightness;
    return float4(colorSample);
}
