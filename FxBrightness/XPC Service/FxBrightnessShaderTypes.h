#pragma once
#import <simd/simd.h>

typedef enum BrightnessVertexInputIndex {
    BVI_Vertices = 0,
    BVI_ViewportSize = 1
} BrightnessVertexInputIndex;

typedef enum BrightnessTextureIndex {
    BTI_InputImage  = 0
} BrightnessTextureIndex;

typedef enum BrightnessFragmentIndex {
    BFI_Brightness  = 0
} BrightnessFragmentIndex;

typedef struct Vertex2D {
    vector_float2 position;
    vector_float2 textureCoordinate;
} Vertex2D;
