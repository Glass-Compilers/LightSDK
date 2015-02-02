#include "globals.h"

sampler2D tex : register(s0);
sampler2D cstrip: register(s1);
sampler2D astrip: register(s2);

//#define 

uniform float4 throttleFactor; // .x = alpha cutoff, .y = alpha boost (clamp), .w - additive/alpha ratio for Crazy shaders
uniform float4 modulateColor;
uniform float4 zOffset;

struct VS_INPUT
{
	float4 pos : POSITION;
	float4 scaleRotLife : TEXCOORD0; // transform matrix
	float2 disp  : TEXCOORD1; // .xy = corner, either (0,0), (1,0), (0,1), or (1,1)
	float2 cline:  TEXCOORD2; // .x = color line [0...32767]
};

struct VS_OUTPUT
{
	float4 pos   : POSITION;
	float3 uvFog : TEXCOORD0;
	float2 colorLookup : TEXCOORD1;
};

float4 rotScale( float4 scaleRotLife )
{
	float cr = cos( scaleRotLife.z );
	float sr = sin( scaleRotLife.z );

	float4 r;
	r.x = cr  * scaleRotLife.x;
	r.y = -sr * scaleRotLife.x;
	r.z =  sr * scaleRotLife.y;
	r.w =  cr * scaleRotLife.y;
	
	return r;
}

float4 mulq( float4 a, float4 b )
{
	float3 i = cross( a.xyz, b.xyz )  + a.w * b.xyz + b.w * a.xyz;
	float  r = a.w * b.w - dot( a.xyz, b.xyz );
	return float4( i, r );
}

float4 conj( float4 a ) { return float4( -a.xyz, a.w ); }

float4 rotate( float4 v, float4 q ) 
{
	return mulq( mulq( q, v ), conj( q ) );
}

float4 axis_angle( float3 axis, float angle )
{
	return float4( sin(angle/2) * axis, cos(angle/2) );
}

VS_OUTPUT vs( VS_INPUT input )
{
	VS_OUTPUT o;
	
	float4 pos  = float4( input.pos.xyz, 1 );
	float2 disp = input.disp.xy * 2 - 1; // -1..1

	input.scaleRotLife *= float4( 1/256.0f, 1/256.0f, 2 * 3.1415926f / 32767, 1 / 32767.0f );
	
	float4 rs = rotScale( input.scaleRotLife );

	pos += G(ViewRight) * dot( disp, rs.xy );
	pos += G(ViewUp) * dot( disp, rs.zw );

        float4 pos2 = pos + G(ViewDir)*zOffset.x; // Z-offset position in world space

        o.pos = mul( G(ViewProjection), pos );
	
	o.uvFog.xy = input.disp.xy;
	o.uvFog.y = 1 - o.uvFog.y;
	o.uvFog.z = (G(FogParams).z - o.pos.w) * G(FogParams).w;
	
	o.colorLookup.x = 1 - max( 0, min(1, input.scaleRotLife.w ) );
	o.colorLookup.y = input.cline.x * (1 / 32767.0f);


        pos2 = mul( G(ViewProjection), pos2 ); // Z-offset position in clip space
        o.pos.z = pos2.z * o.pos.w/pos2.w;     // Only need z
        

	return o;
}


float4 psAdd( VS_OUTPUT input ) : COLOR0 // #0
{
	float4 texcolor = tex2D( tex, input.uvFog.xy );
	float4   vcolor = tex2D( cstrip, input.colorLookup.xy );
           vcolor.a = tex2D( astrip, input.colorLookup.xy ).r;
	
	float4 result;

	result.rgb = (texcolor.rgb + vcolor.rgb) * modulateColor.rgb;
	result.a   = texcolor.a   * vcolor.a;
	result.rgb *= result.a;

	result.rgb = lerp( 0.0f.xxx, result.rgb, saturate( input.uvFog.zzz ) );
	return result;
}

float4 psModulate( VS_OUTPUT input ) : COLOR0 // #1
{

	float4 texcolor = tex2D( tex, input.uvFog.xy );
	float4   vcolor = tex2D( cstrip, input.colorLookup.xy ) * modulateColor;
           vcolor.a = tex2D( astrip, input.colorLookup.xy ).r * modulateColor.a;

	float4 result;

	result.rgb = texcolor.rgb * vcolor.rgb;
	result.a   = texcolor.a   * vcolor.a;
	
	result.rgb = lerp( G(FogColor).rgb, result.rgb, saturate( input.uvFog.zzz ) );
	return result;
}

float4 psMultiplicative( VS_OUTPUT input ) : COLOR0 // #2
{

	float4 texcolor = tex2D( tex, input.uvFog.xy );
	float4 vcolor = tex2D( cstrip, input.colorLookup.xy ) * modulateColor;
        vcolor.a = tex2D( astrip, input.colorLookup.xy ).r * modulateColor.a;

	float4 result = lerp( 1.0f.xxxx, texcolor, vcolor.aaaa );

	result.rgb = lerp( 1.0f.xxx, result.rgb, saturate( input.uvFog.zzz ) );
	return result;
}


float4 psBlend( VS_OUTPUT input ) : COLOR0 // #3
{
	float4 texcolor = tex2D( tex, input.uvFog.xy );
	float4 vcolor   = tex2D( cstrip, input.colorLookup.xy );
           vcolor.a = tex2D( astrip, input.colorLookup.xy ).r;
	
	float4 result;
	
	// texture color bands 0..127 - transparency (background...particle color)
	//                    128..255 - (particle color .. texture color)

	if( texcolor.a < 0.5f )
	{
		result.rgb = vcolor.rgb * modulateColor.rgb * (2 * texcolor.a);
	}
	else
	{
		result.rgb = lerp( vcolor.rgb * modulateColor.rgb, texcolor.rgb, 2*texcolor.a-1 );
	}
	
	vcolor.a   *= modulateColor.a;
	result.a    = vcolor.a;
	result.rgb *= vcolor.a;

	result.rgb = lerp( 0.f.xxx, result.rgb, saturate( input.uvFog.zzz ) );
	return result;
}

// - this shader is crazy
// - used instead of additive particles to help see bright particles (e.g. fire) on top of extremely bright backgrounds 
// - requires ONE | INVSRCALPHA blend mode, useless otherwise
// - does not use color strip texture
// - outputs a blend between additive blend and alpha blend in fragment alpha
// - ratio multiplier is in throttleFactor.w
float4 psCrazy( VS_OUTPUT input ) : COLOR0
{
	float4  texcolor = tex2D( tex, input.uvFog.xy );
	float4  vcolor   = float4(1,0,0,0); //tex2D( cstrip, input.colorLookup.xy ); // not actually used
            vcolor.a = tex2D( astrip, input.colorLookup.xy ).r;
	float   blendRatio = throttleFactor.w; // yeah yeah
	
	float4 result;

	result.rgb = (texcolor.rgb ) * modulateColor.rgb  * vcolor.a * texcolor.a;
	result.a   = blendRatio * texcolor.a  * vcolor.a;

	result = lerp( 0.0f.xxxx, result, saturate( input.uvFog.zzzz ) );
	return result;
}

float4 psCrazySparkles( VS_OUTPUT input ) : COLOR0
{
	float4  texcolor = tex2D( tex, input.uvFog.xy );
	float4  vcolor   = tex2D( cstrip, input.colorLookup.xy );
            vcolor.a = tex2D( astrip, input.colorLookup.xy ).r;
	float   blendRatio = throttleFactor.w;
	
	float4 result;

	if( texcolor.a < 0.5f )
	{
		result.rgb = vcolor.rgb * modulateColor.rgb * (2 * texcolor.a);
	}
	else
	{
		result.rgb = lerp( vcolor.rgb * modulateColor.rgb, texcolor.rgb, 2*texcolor.a-1 );
	}
	
	//vcolor.a   *= modulateColor.a;
	result.rgb *= vcolor.a;
	result.a    = blendRatio * texcolor.a * vcolor.a;
	
	result = lerp( 0.0f.xxxx, result, saturate( input.uvFog.zzzz ) );
	return result;
}


///////////////////////////////////////////////////////////////////////////////////

// legacy stuff - to be removed!

uniform float4 colorBias;

float4 psAdd_LEGACY( VS_OUTPUT input ) : COLOR0 // #0
{
	float4 vcolor = tex2D( cstrip, input.colorLookup.xy )   * modulateColor;
	     vcolor.a = tex2D( astrip, input.colorLookup.xy ).r * modulateColor.a;
	
	float4 color = tex2D( tex, input.uvFog.xy );
	float4 result = float4( vcolor.rgb + color.rgb + colorBias.rgb, color.a * vcolor.a );
	result.rgb = lerp( G(FogColor).rgb, result.rgb, saturate( input.uvFog.zzz ) );
	return result;
}

float4 psMul_LEGACY( VS_OUTPUT input ) : COLOR0 // #1
{
	float4 vcolor = tex2D( cstrip, input.colorLookup.xy )   * modulateColor;
 	     vcolor.a = tex2D( astrip, input.colorLookup.xy ).r * modulateColor.a;

	float4 color = tex2D( tex, input.uvFog.xy );
	float4 result = vcolor * color;
	result.rgb = lerp( G(FogColor).rgb, result.rgb, saturate( input.uvFog.zzz ) );
	return result;
}
