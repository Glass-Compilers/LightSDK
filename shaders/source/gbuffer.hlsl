#include "globals.h"

// .xy = gbuffer width/height, .zw = inverse gbuffer width/height
uniform float4 TextureSize;

sampler2D   tex : register(s0);

struct v2f
{
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

#ifdef GLSL
float4 convertPosition(float4 p)
{
	return p;
}

float2 convertUv(float4 p)
{
	return p.xy * 0.5 + 0.5;
}
#else
float4 convertPosition(float4 p)
{
	// half-pixel offset
	return p + float4(-TextureSize.z, TextureSize.w, 0, 0);
}

float2 convertUv(float4 p)
{
	return p.xy * float2(0.5, -0.5) + 0.5;
}
#endif


v2f gbufferVS( in float4 pos : POSITION )
{
    v2f o;
    o.pos = convertPosition(pos);
    o.uv =  convertUv(pos);
    return o;
}


float4 gbufferPS( v2f i ) : COLOR0
{
    return tex2D( tex, i.uv );
}
