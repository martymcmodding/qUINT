/*=============================================================================

	ReShade 4 effect file
    github.com/martymcmodding     

	Support me:
   		paypal.me/mcflypg
   		patreon.com/mcflypg   

    Ambient Obscurance with Indirect Lighting "MXAO"

    BETA VERSION, FEATURESET SUBJECT TO CHANGE!

    by Marty McFly / P.Gilcher
        part of qUINT shader library for ReShade 4

    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/

#ifndef MXAO_HALFRES_INPUT
 #define MXAO_HALFRES_INPUT     1   //[0 or 1]      Uses half resolution depth and color inputs, improving performance, yet reducing quality
#endif
    
#ifndef MXAO_ENABLE_IL
 #define MXAO_ENABLE_IL			0	//[0 or 1]	    Enables Indirect Lighting calculation. Will cause a major fps hit.
#endif


/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform int MXAO_GLOBAL_SAMPLE_QUALITY_PRESET <
	ui_type = "combo";
    ui_label = "Sample Quality";
	ui_items = "Very Low  (4 samples)\0Low       (8 samples)\0Medium    (16 samples)\0High      (24 samples)\0Very High (32 samples)\0Ultra     (64 samples)\0Maximum   (255 samples)\0";
	ui_tooltip = "Global quality control, main performance knob. Higher radii might require higher quality.";
    ui_category = "Global";
> = 2;

uniform int SHADING_RATE <
	ui_type = "combo";
    ui_label = "Shading Rate";
	ui_items = "Full Rate\0Half Rate\0Quarter Rate\0";
	ui_tooltip = "0: render all pixels each frame\n1: render only 50% of pixels each frame\n2: render only 25% of pixels each frame";
    ui_category = "Global";
> = 1;

uniform float MXAO_SAMPLE_RADIUS <
	ui_type = "drag";
	ui_min = 0.5; ui_max = 20.0;
    ui_label = "Sample Radius";
	ui_tooltip = "Sample radius of MXAO, higher means more large-scale occlusion with less fine-scale details.";  
    ui_category = "Global";      
> = 2.5;

uniform float MXAO_SAMPLE_NORMAL_BIAS <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.8;
    ui_label = "Normal Bias";
    ui_tooltip = "Occlusion Cone bias to reduce self-occlusion of surfaces that have a low angle to each other.";
    ui_category = "Global";
> = 0.2;

uniform float MXAO_SSAO_AMOUNT <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 4.0;
    ui_label = "Ambient Occlusion Amount";        
	ui_tooltip = "Intensity of AO effect. Can cause pitch black clipping if set too high.";
    ui_category = "Blending";
> = 1.00;

#if(MXAO_ENABLE_IL != 0)
uniform float MXAO_SSIL_AMOUNT <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 12.0;
    ui_label = "Indirect Lighting Amount";
    ui_tooltip = "Intensity of IL effect. Can cause overexposured white spots if set too high.";
    ui_category = "Blending";
> = 4.0;

uniform float MXAO_SSIL_SATURATION <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 3.0;
    ui_label = "Indirect Lighting Saturation";
    ui_tooltip = "Controls color saturation of IL effect.";
    ui_category = "Blending";
> = 1.0;
#endif

uniform int MXAO_BLEND_TYPE <
	ui_type = "slider";
	ui_min = 0; ui_max = 3;
    ui_label = "Blending Mode";
	ui_tooltip = "Different blending modes for merging AO/IL with original color.\0Blending mode 0 matches formula of MXAO 2.0 and older.";
    ui_category = "Blending";
> = 0;

uniform float MXAO_FADE_DEPTH <
	ui_type = "drag";
    ui_label = "Fade Out Distance";
	ui_min = 0.00; ui_max = 1.00;
	ui_tooltip = "Fadeout distance for MXAO. Higher values show MXAO in farther areas.";
    ui_category = "Blending";
> = 0.25;

uniform bool MXAO_DEBUG_VIEW_ENABLE <
    ui_label = "Enable Debug View";
    ui_category = "Debug";
> = false;
/*
uniform float4 tempF1 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF2 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);

uniform float4 tempF3 <
    ui_type = "drag";
    ui_min = -100.0;
    ui_max = 100.0;
> = float4(1,1,1,1);
*/
#warning "Experimental, do not use in presets. Featureset subject to change."


/*=============================================================================
	Textures, Samplers, Globals, Structs
=============================================================================*/

//do NOT change anything here. "hurr durr I changed this and now it works"
//you ARE breaking things down the line, if the shader does not work without changes
//here, it's by design.

#define RESHADE_QUINT_COMMON_VERSION_REQUIRE 202
#define RESHADE_QUINT_EFFECT_DEPTH_REQUIRE

#include "qUINT\Global.fxh"
#include "qUINT\Depth.fxh"
#include "qUINT\Projection.fxh"
#include "qUINT\Normal.fxh"

//integer divide, rounding up
#define CEIL_DIV(num, denom) (((num - 1) / denom) + 1)

#define DEINTERLEAVE_TILE_COUNT 4u 

uniform uint FRAME_COUNT < source = "framecount"; >;

#if MXAO_HALFRES_INPUT != 0
 #define SOURCE_SCALE 2
#else 
 #define SOURCE_SCALE 1
#endif

texture ZSrc { Width = BUFFER_WIDTH/SOURCE_SCALE;   Height = BUFFER_HEIGHT/SOURCE_SCALE;   Format = R16F;  };
texture CSrc { Width = BUFFER_WIDTH/SOURCE_SCALE;   Height = BUFFER_HEIGHT/SOURCE_SCALE;   Format = RGB10A2;  };
texture NSrc { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGB10A2; };
sampler sZSrc { Texture = ZSrc; MinFilter=POINT; MipFilter=POINT; MagFilter=POINT;};
sampler sCSrc { Texture = CSrc;	MinFilter=POINT; MipFilter=POINT; MagFilter=POINT;};
sampler sNSrc { Texture = NSrc;	MinFilter=POINT; MipFilter=POINT; MagFilter=POINT;};

texture AORaw { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA8; };
sampler sAORaw { Texture = AORaw; MinFilter=POINT; MipFilter=POINT; MagFilter=POINT;};

texture MXAOGbuf { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA16F; };
sampler sMXAOGbuf { Texture = MXAOGbuf; };
texture AOFilterT1 { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA8; };
sampler sAOFilterT1 { Texture = AOFilterT1; };
texture AOFilterT2 { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA8; };
sampler sAOFilterT2 { Texture = AOFilterT2; };

/*=============================================================================
	Vertex Shader
=============================================================================*/

struct VSOUT
{
    float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
};

VSOUT VS_Main(in uint id : SV_VertexID)
{
    VSOUT o;
    VS_FullscreenTriangle(id, o.vpos, o.uv); 
    return o;
}

/*=============================================================================
	Functions
=============================================================================*/

float2 deinterleave_uv(float2 uv)
{
    float2 splituv = uv * DEINTERLEAVE_TILE_COUNT;
    float2 splitoffset = floor(splituv) - DEINTERLEAVE_TILE_COUNT * 0.5 + 0.5;
    splituv = frac(splituv) + splitoffset * BUFFER_PIXEL_SIZE;
    return splituv;
}
float2 reinterleave_uv(float2 uv)
{
    uint2 whichtile = floor(uv / BUFFER_PIXEL_SIZE) % DEINTERLEAVE_TILE_COUNT;
    float2 newuv = uv + whichtile;
    newuv /= DEINTERLEAVE_TILE_COUNT;
    return newuv;
}

void shading_rate(float2 uv)
{
    switch(SHADING_RATE)
    {
        case 0: //full rate
            break;
        case 1: //half rate
        {
            float2 tile = floor(uv * 3.999999);
            float checker = dot(tile, 1) % 2;
            float f = FRAME_COUNT % 2;
            if(abs(f - checker) > 0.25) discard;
            break;
        }        
        case 2: //quarter rate - not using bayer atm, could be improved
        {
            float2 tile = floor(uv * 3.999999);
            float checker = dot(tile % 2, float2(1, 2)); // dot(tile, float2(1, 2)) % 4;
            float f = FRAME_COUNT % 4;
            if(abs(f - checker) > 0.25) discard;            
            break; 
        }      
    }
}

float4 filter(float2 uv, sampler aosampler, int iter)
{
    float4 sum = 0;
    float wsum = 0;

    float4 gbuf_center = tex2D(sMXAOGbuf, uv);

    for(int y = 0; y <= 1; y++)
    for(int x = 0; x <= 1; x++)
    {
        float2 offs = float2(x, y) * 2.0 - 1.5 + iter * 2;

        float4 ao   = tex2Dlod(aosampler, uv + offs * BUFFER_PIXEL_SIZE, 0);
        float4 gbuf = tex2Dlod(sMXAOGbuf, uv + offs * BUFFER_PIXEL_SIZE, 0);

        float wn = saturate(dot(gbuf_center.xyz, gbuf.xyz) * 2.0 - 1.0);
        float wz = 6.0 * (1.0 - gbuf.w / gbuf_center.w);
        wz = saturate(0.5 - lerp(wz, abs(wz), 0.75)); 
        float w = wz * wn + 0.001;

        sum += ao * w;
        wsum += w;
    }
    return sum / wsum;
}

/*=============================================================================
	Pixel Shaders
=============================================================================*/

void PS_Deferred0(in VSOUT i, out MRT2 o)
{
    float2 deinter_uv = deinterleave_uv(i.uv);
    o.t0 = -Depth::get_linear_depth(deinter_uv);
    o.t1 = float4(tex2Dlod(ColorInput, deinter_uv, 0).rgb, 0);
}

void PS_Deferred1(in VSOUT i, out float4 t0 : SV_Target0)
{
    float2 deinter_uv = deinterleave_uv(i.uv);
    t0 = float4(Normal::normal_from_depth(deinter_uv).xyz * 0.5 + 0.5, 0);
}

void PS_MXAO(in VSOUT i, out float4 o : SV_Target0)
{
    shading_rate(i.uv);
    float4 uv = float4(i.uv, deinterleave_uv(i.uv));

    float z = Projection::depth_to_z(Depth::get_linear_depth(uv.zw));
    float3 p = Projection::uv_to_proj(uv.zw, z); 
    float3 n = tex2D(sNSrc, uv.xy).xyz * 2.0 - 1.0;

    p = p * 0.995 + n * Projection::z_to_depth(z);

    static const int samples_per_preset[7] = {4, 8, 16, 24, 32, 64, 255};
    int SAMPLES_PER_PIXEL = samples_per_preset[MXAO_GLOBAL_SAMPLE_QUALITY_PRESET];

    float scaled_radius = 0.25 * MXAO_SAMPLE_RADIUS / p.z / SAMPLES_PER_PIXEL;
    //scaled_radius += BUFFER_PIXEL_SIZE.x * tempF2.z;  

    float falloff_factor = -rcp(MXAO_SAMPLE_RADIUS * MXAO_SAMPLE_RADIUS * 4.0);
    float jitter = dot(floor(uv.xy * DEINTERLEAVE_TILE_COUNT), float2(rcp(DEINTERLEAVE_TILE_COUNT*DEINTERLEAVE_TILE_COUNT), rcp(DEINTERLEAVE_TILE_COUNT))) + rcp(2.0 * DEINTERLEAVE_TILE_COUNT*DEINTERLEAVE_TILE_COUNT);

    float2 sample_dir;
    sincos(2.3999632 * 16 * jitter, sample_dir.x, sample_dir.y);
    sample_dir *= scaled_radius;

    float4 mxao = 0;

    const float4 texture_scale = float2(1.0 / DEINTERLEAVE_TILE_COUNT, 1.0).xxyy * BUFFER_ASPECT_RATIO.xyxy;

    [loop]
    for(uint j = 0; j < SAMPLES_PER_PIXEL; j++)
    {
        float4 tap_uv = uv + sample_dir.xyxy * (j + jitter) * texture_scale;
        sample_dir = mul(sample_dir, float2x2(0.76465, -0.64444, 0.64444, 0.76465)); 

        if(!all(saturate(tap_uv - tap_uv * tap_uv))) continue;

        float zz = Projection::depth_to_z(-tex2Dlod(sZSrc, tap_uv.xy, 0).x);
        float3 v = Projection::uv_to_proj(tap_uv.zw, zz) - p;
        float vv = dot(v, v);
        float vn = dot(v, n) * rsqrt(vv);

        float ao = saturate(1.0 + falloff_factor * vv) * saturate(vn - MXAO_SAMPLE_NORMAL_BIAS);

#if MXAO_ENABLE_IL != 0
        [branch]
        if(ao > 0.1)
        {
            float3 il = tex2Dlod(sCSrc, tap_uv.xy, 0).rgb;
            float3 sn = tex2Dlod(sNSrc, tap_uv.xy, 0).xyz * 2.0 - 1.0;
            
            il *= saturate(ao * 1.11 - 0.11);
            il *= saturate(dot(sn, -v) * rsqrt(vv));
            mxao += float4(il, ao);
        }
        else 
#endif
        mxao.w += ao;
    }
    mxao /= SAMPLES_PER_PIXEL * 0.5;
    o = sqrt(mxao);
}

void PS_Reinterleave(in VSOUT i, out MRT2 o)
{
    float2 newuv = reinterleave_uv(i.uv);
    o.t0 = tex2D(sAORaw, newuv);
    //faster to recompute than reinterleave, also halfres
    o.t1 = float4(Normal::normal_from_depth(i.uv), Depth::get_linear_depth(i.uv));
}

void PS_Filter1(in VSOUT i, out float4 o : SV_Target0)
{
    o = filter(i.uv, sAOFilterT1, 0);
}

void PS_Filter2AndCombine(in VSOUT i, out float4 o : SV_Target0)
{
    float4 mxao = filter(i.uv, sAOFilterT2, 1);  
    mxao *= mxao;
    float4 rawmxao = mxao;
    float4 color = tex2D(ColorInput, i.uv);

    static const float3 lumcoeff = float3(0.2126, 0.7152, 0.0722);
    float colorgray = dot(color.rgb, lumcoeff);
    float blendfact = 1.0 - colorgray;

#if(MXAO_ENABLE_IL != 0)
	mxao.rgb  = lerp(dot(mxao.rgb, lumcoeff), mxao.rgb, MXAO_SSIL_SATURATION) * MXAO_SSIL_AMOUNT * 2.0;
#else
    mxao.rgb = 0.0;
#endif

//#if(MXAO_HIGH_QUALITY == 0)
	mxao.w  = 1.0 - pow(saturate(1.0 - mxao.w), MXAO_SSAO_AMOUNT * 2.0);
//#else
//   mxao.w  = 1.0 - pow(saturate(1.0 - mxao.w), MXAO_SSAO_AMOUNT);
//#endif
    float dist = saturate(length(Projection::uv_to_proj(i.uv)) / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
    float fade = exp(-dist * rcp(MXAO_FADE_DEPTH * MXAO_FADE_DEPTH * 8.0 + 0.001));
    mxao *= fade;
    rawmxao *= fade;

    if(MXAO_BLEND_TYPE == 0)
    {
        color.rgb -= (mxao.www - mxao.rgb) * blendfact * color.rgb;
    }
    else if(MXAO_BLEND_TYPE == 1)
    {
        color.rgb = color.rgb * saturate(1.0 - mxao.www * blendfact * 1.2) + mxao.rgb * blendfact * colorgray * 2.0;
    }
    else if(MXAO_BLEND_TYPE == 2)
    {
        float colordiff = saturate(2.0 * distance(normalize(color.rgb + 1e-6),normalize(mxao.rgb + 1e-6)));
        color.rgb = color.rgb + mxao.rgb * lerp(color.rgb, dot(color.rgb, 0.3333), colordiff) * blendfact * blendfact * 4.0;
        color.rgb = color.rgb * (1.0 - mxao.www * (1.0 - dot(color.rgb, lumcoeff)));
    }
    else if(MXAO_BLEND_TYPE == 3)
    {
        color.rgb /= 1.01 - color.rgb;
        color.rgb = color.rgb * (1.0 + mxao.rgb * 2.0) / (1.0 + rawmxao.w  * MXAO_SSAO_AMOUNT * 2.0);
        color.rgb /= 1.01 + color.rgb;
    }

    if(MXAO_DEBUG_VIEW_ENABLE)
    {
        color.rgb = max(0.0, 1.0 - mxao.www + mxao.rgb);
        color.rgb *= (MXAO_ENABLE_IL != 0) ? 0.5 : 1.0;
    }
       
    o = color;
}

/*=============================================================================
	Techniques
=============================================================================*/

technique qUINT_MXAO
{
    pass
	{
		VertexShader = VS_Main;
		PixelShader  = PS_Deferred0;
        RenderTarget0 = ZSrc;
        RenderTarget1 = CSrc;
    }
    pass
	{
		VertexShader = VS_Main;
		PixelShader  = PS_Deferred1;
        RenderTarget0 = NSrc;
    }
    pass
	{
        VertexShader = VS_Main;
		PixelShader  = PS_MXAO;
        RenderTarget = AORaw;
    }
    pass
	{
        VertexShader = VS_Main;
		PixelShader  = PS_Reinterleave;
        RenderTarget0 = AOFilterT1;
        RenderTarget1 = MXAOGbuf;
    }
    pass
	{
        VertexShader = VS_Main;
		PixelShader  = PS_Filter1;
        RenderTarget0 = AOFilterT2;
    }
    pass
	{
        VertexShader = VS_Main;
		PixelShader  = PS_Filter2AndCombine;
    }
}
