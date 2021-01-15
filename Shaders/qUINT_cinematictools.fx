/*=============================================================================

	ReShade 4 effect file
    github.com/martymcmodding

	Support me:
   		paypal.me/mcflypg
   		patreon.com/mcflypg

    Experimental screenshot framing tool for ReShade

    * Unauthorized copying of this file, via any medium is strictly prohibited
 	* Proprietary and confidential

=============================================================================*/

uniform float2 BACKDROP_DIST <
    ui_type = "drag";
    ui_label = "Distance and Transition";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Backdrop";
> = float2(0.350, 0.1);

uniform float BACKDROP_INT <
    ui_type = "slider";
    ui_label = "Intensity";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Backdrop";
> = 1.0;

uniform int BACKDROP_MASKMODE <
	ui_type = "radio";
    ui_label = "Mask Mode";
	ui_items = "Plane\0Sphere\0";
    ui_category = "Backdrop";
> = 0;

uniform float3 BACKDROP_TINT <
	ui_type = "color";
	ui_label = "Color";
    ui_category = "Backdrop";
> = float3(1.0, 1.0, 1.0);

uniform float4 BACKDROP_IMPRESSION_CTRL <
    ui_type = "drag";
    ui_label = "Impression:\nRotation | Scale | Offset | Intensity";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_category = "Backdrop";
> = float4(0.467, 0.5, 0.5, 1.0);

uniform int LETTERBOX_PRESET <
	ui_type = "combo";
    ui_label = "Preset";
	ui_items = " Custom \0 1:1 \0 5:4 \0 4:3 \0 16:10 \0 16:9 \0 1.85:1 \0 2:1 \0 2.35:1 \0 ";
    ui_category = "Letterbox";
> = 0;

uniform int2 LETTERBOX_CUSTOMRATIO <
	ui_type = "slider";
    ui_min = 1;
    ui_max = 20;
    ui_label = "Custom Ratio";
    ui_category = "Letterbox";
> = int2(1, 1);

#define RESHADE_QUINT_COMMON_VERSION_REQUIRE 202
#define RESHADE_QUINT_EFFECT_DEPTH_REQUIRE
#include "qUINT_common.fxh"

/*=============================================================================
	Vertex Shader
=============================================================================*/

struct VSOUT
{
	float4                  vpos        : SV_Position;
    float2                  uv          : TEXCOORD0;
};

VSOUT VSMain(in uint id : SV_VertexID)
{
    VSOUT o;
    PostProcessVS(id, o.vpos, o.uv); //use original fullscreen triangle VS
    return o;
}

/*=============================================================================
	Functions
=============================================================================*/

float2 rotate(float2 v, float ang)
{
    float2 sc; sincos(radians(ang), sc.x, sc.y);
    float2x2 rot = float2x2(sc.y, -sc.x, sc.x, sc.y);
    return mul(v, rot);
}

#define linearstep(_a, _b, _x) saturate((_x - _a) * rcp(_b - _a))

float3 dither(in VSOUT i)
{
    const float2 magicdot = float2(0.75487766624669276, 0.569840290998);
    const float3 magicadd = float3(0, 0.025, 0.0125) * dot(magicdot, 1);

    const int bit_depth = 8; //TODO: add BUFFER_COLOR_DEPTH once it works
    const float lsb = exp2(bit_depth) - 1;

    float3 dither = frac(dot(i.vpos.xy, magicdot) + magicadd);
    dither /= lsb;
    
    return dither;
}

float3 impression(in VSOUT i)
{
    float x = (rotate(i.uv - 0.5, 360.0 * BACKDROP_IMPRESSION_CTRL.x).x + 0.5) * BACKDROP_IMPRESSION_CTRL.y * BACKDROP_IMPRESSION_CTRL.y + BACKDROP_IMPRESSION_CTRL.z * 32.0;

    float2 randwalk;
    randwalk.x = sin(2.0 * x) + sin(3.1415152 * x);
    randwalk.y = sin(2.0 * x + 1.44) + sin(3.1415152 * x + 88.123);

    randwalk = randwalk * 0.25 + 0.5;

    //hide linear interpolation
    randwalk *= qUINT::SCREEN_SIZE;
    randwalk -= 0.5;
    float2 a = frac(randwalk);
    randwalk = floor(randwalk) + a * a * (3.0 - 2.0 * a);
    randwalk += 0.5;
    randwalk *= qUINT::PIXEL_SIZE;
    
    return tex2D(qUINT::sBackBufferTex, randwalk).rgb + dither(i);
}

/*=============================================================================
	Pixel Shaders
=============================================================================*/

uniform float timer < source = "timer"; >;

void PSMain(in VSOUT i, out float3 color : SV_Target)
{
    color = tex2D(qUINT::sBackBufferTex, i.uv).rgb;
    float depth = qUINT::linear_depth(i.uv);    

    //add backdrop
    float position = BACKDROP_DIST.x * BACKDROP_DIST.x * BACKDROP_DIST.x;
    float range = BACKDROP_DIST.y * BACKDROP_DIST.y;
    float2 clip_planes = position + float2(-range, range) * 0.05;
    float distance = length(0.600 * depth * qUINT::ASPECT_RATIO.yxy * float3(i.uv * 2.0 - 1.0, 1.0));

    float metric = BACKDROP_MASKMODE == 0 ? depth 
                 : BACKDROP_MASKMODE == 1 ? distance 
                 : depth;

    float backdrop_mask = linearstep(clip_planes.x, clip_planes.y, metric);
    backdrop_mask = smoothstep(0, 1, backdrop_mask);

    float3 backdrop = lerp(BACKDROP_TINT, impression(i), BACKDROP_IMPRESSION_CTRL.w);
    color = lerp(color, backdrop, backdrop_mask * BACKDROP_INT);

    //apply letterbox
    float current_aspect = qUINT::ASPECT_RATIO.y;
    float target_aspect  = LETTERBOX_PRESET == 1 ? 1.0 
                         : LETTERBOX_PRESET == 2 ? 5.0/4.0 
                         : LETTERBOX_PRESET == 3 ? 4.0/3.0     
                         : LETTERBOX_PRESET == 4 ? 16.0/10.0
                         : LETTERBOX_PRESET == 5 ? 16.0/9.0
                         : LETTERBOX_PRESET == 6 ? 1.85
                         : LETTERBOX_PRESET == 7 ? 2.0
                         : LETTERBOX_PRESET == 8 ? 2.35
                         : float(LETTERBOX_CUSTOMRATIO.x) / float(LETTERBOX_CUSTOMRATIO.y);

    float2 nuv = i.uv * 2.0 - 1.0;
    float2 correction = float2(current_aspect / target_aspect, 1);

    nuv *= correction.x > 1.0 ? correction : rcp(correction.yx);
	color *= all(saturate(1.0 - nuv * nuv));
}

/*=============================================================================
	Techniques
=============================================================================*/

technique FrameTool
{
    pass
    {
        VertexShader = VSMain;
        PixelShader  = PSMain;
    }
}
