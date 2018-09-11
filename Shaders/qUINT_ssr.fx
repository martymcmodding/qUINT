/*=============================================================================

	ReShade 3 effect file
    github.com/martymcmodding

	Support me:
   		paypal.me/mcflypg
   		patreon.com/mcflypg

    Screen-Space Reflections
    by Marty McFly / P.Gilcher
    part of qUINT shader library for ReShade 3

    CC BY-NC-ND 3.0 licensed.

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/


/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform float SSR_FIELD_OF_VIEW <
	ui_type = "drag";
	ui_min = 0.00; ui_max = 100.00;
	ui_label = "Vertical Field of View";
	ui_tooltip = "Vertical FoV, should match camera FoV but since ReShade's\ndepth linearization is not always precise, this value\nmight differ from the actual value. Just set to what looks best.";
	ui_category = "Global";
> = 50.0;

uniform float SSR_FRESNEL_K <
	ui_type = "drag";
	ui_min = 0.00; ui_max = 1.00;
	ui_label = "Reflection Coefficient";
	ui_tooltip = "qUINT uses Schlick's fresnel approximation.\nThis parameter represents the reflection intensity when viewed head on.";
	ui_category = "Global";
> = 0.0;

uniform float SSR_FRESNEL_EXP <
	ui_type = "drag";
	ui_min = 1.00; ui_max = 10.00;
	ui_label = "Reflection Exponent";
	ui_tooltip = "qUINT uses Schlick's fresnel approximation.\nThis parameter represents the power of the angle falloff.\nHigher values restrict reflections to very flat angles.\nOriginal Schlick value: 5.";
	ui_category = "Global";
> = 5.0;

uniform float SSR_FADE_DIST <
	ui_type = "drag";
	ui_min = 0.001; ui_max = 1.00;
	ui_label = "Fade Distance";
	ui_tooltip = "Distance where reflection is completely faded out.\n1 means infinite distance.";
	ui_category = "Global";
> = 0.8;

uniform float SSR_RAY_INC <
	ui_type = "drag";
	ui_min = 1.01; ui_max = 3.00;
	ui_label = "Ray Increment";
	ui_tooltip = "Rate of ray step size growth.\nA parameter of 1.0 means same sized steps,\n2.0 means the step size doubles each iteration.";
	ui_category = "Ray Tracing";
> = 1.6;

uniform float SSR_ACCEPT_RANGE <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 12.00;
	ui_label = "Acceptance Range";
	ui_tooltip = "Acceptable error for ray intersection. Larger values will cause more coherent but incorrect reflections.";
	ui_category = "Ray Tracing";
> = 2.5;

uniform float SSR_JITTER_AMOUNT <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.00;
	ui_label = "Ray Jitter Amount";
	ui_tooltip = "Changes ray step size randomly per pixel to produce\na more coherent reflection at the cost of noise that needs to be filtered away.";
	ui_category = "Ray Tracing";
> = 0.25;

uniform float SSR_FILTER_SIZE <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 5.00;
	ui_label = "Filter Kernel Size";
	ui_tooltip = "Size of spatial filter, higher values create more blurry reflections at the cost of detail.";
	ui_category = "Filtering and Details";
> = 0.2;

uniform float SSR_RELIEF_AMOUNT <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.00;
	ui_label = "Surface Relief Height";
	ui_tooltip = "Strength of embossed texture relief. Higher values cause more bumpy surfaces.";
	ui_category = "Filtering and Details";
> = 0.05;

uniform float SSR_RELIEF_SCALE <
	ui_type = "drag";
	ui_min = 0.1; ui_max = 1.00;
	ui_label = "Surface Relief Scale";
	ui_tooltip = "Scale of embossed texture relief, lower values cause more high frequency relief.";
	ui_category = "Filtering and Details";
> = 0.35;

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

/*=============================================================================
	Textures, Samplers, Globals
=============================================================================*/

#include "qUINT_common.fxh"

texture2D SSR_ColorTex 	{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; AddressU = MIRROR;};
sampler2D sSSR_ColorTex	{ Texture = SSR_ColorTex;	};

/*=============================================================================
	Vertex Shader
=============================================================================*/

struct SSR_VSOUT
{
	float4   vpos        : SV_Position;
    float2   uv          : TEXCOORD0;
    float3   uvtoviewADD : TEXCOORD4;
    float3   uvtoviewMUL : TEXCOORD5;
};

SSR_VSOUT VS_SSR(in uint id : SV_VertexID)
{
    SSR_VSOUT o;
    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;       
    o.vpos = float4(o.uv.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    
    o.uvtoviewADD = float3(-1.0,-1.0,1.0);
    o.uvtoviewMUL = float3(2.0,2.0,0.0);

  	//uncomment to enable perspective-correct position recontruction. Minor difference for common FoV's
    //static const float SSR_FIELD_OF_VIEW = 70.0; //vertical FoV

    o.uvtoviewADD = float3(-tan(radians(SSR_FIELD_OF_VIEW * 0.5)).xx,1.0) * float3(qUINT::ASPECT_RATIO, 1);
	o.uvtoviewMUL = float3(-2.0 * o.uvtoviewADD.xy,0.0);

    return o;
}

/*=============================================================================
	Functions
=============================================================================*/

float3 get_position_from_uv(in float2 uv, in SSR_VSOUT i)
{
    return (uv.xyx * i.uvtoviewMUL + i.uvtoviewADD) * qUINT::linear_depth(uv) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
}

float2 get_uv_from_position(in float3 pos, in SSR_VSOUT i)
{
	return pos.xy / (i.uvtoviewMUL.xy * pos.z) - i.uvtoviewADD.xy/i.uvtoviewMUL.xy;
}

float4 get_normal_and_edges_from_depth(in SSR_VSOUT i)
{
	float3 single_pixel_offset = float3(qUINT::PIXEL_SIZE, 0);

	float3 position              =              get_position_from_uv(i.uv, i);
	float3 position_delta_x1 	 = - position + get_position_from_uv(i.uv + single_pixel_offset.xz, i);
	float3 position_delta_x2 	 =   position - get_position_from_uv(i.uv - single_pixel_offset.xz, i);
	float3 position_delta_y1 	 = - position + get_position_from_uv(i.uv + single_pixel_offset.zy, i);
	float3 position_delta_y2 	 =   position - get_position_from_uv(i.uv - single_pixel_offset.zy, i);

	position_delta_x1 = lerp(position_delta_x1, position_delta_x2, abs(position_delta_x1.z) > abs(position_delta_x2.z));
	position_delta_y1 = lerp(position_delta_y1, position_delta_y2, abs(position_delta_y1.z) > abs(position_delta_y2.z));

	float deltaz = abs(position_delta_x1.z * position_delta_x1.z - position_delta_x2.z * position_delta_x2.z)
				 + abs(position_delta_y1.z * position_delta_y1.z - position_delta_y2.z * position_delta_y2.z);

	return float4(normalize(cross(position_delta_y1, position_delta_x1)), deltaz);
}

float3 get_normal_from_color(float2 uv, float2 offset, float scale, float sharpness)
{
    const float3 lumCoeff = float3(0.299,0.587,0.114);
 
    float hpx = dot(tex2Dlod(qUINT::sBackBufferTex, float4(uv + float2(offset.x,0.0),0,0)).xyz,lumCoeff) * scale;
    float hmx = dot(tex2Dlod(qUINT::sBackBufferTex, float4(uv - float2(offset.x,0.0),0,0)).xyz,lumCoeff) * scale;
    float hpy = dot(tex2Dlod(qUINT::sBackBufferTex, float4(uv + float2(0.0,offset.y),0,0)).xyz,lumCoeff) * scale;
    float hmy = dot(tex2Dlod(qUINT::sBackBufferTex, float4(uv - float2(0.0,offset.y),0,0)).xyz,lumCoeff) * scale;

    float dpx = qUINT::linear_depth(uv + float2(offset.x,0.0));
    float dmx = qUINT::linear_depth(uv - float2(offset.x,0.0));
    float dpy = qUINT::linear_depth(uv + float2(0.0,offset.y));
    float dmy = qUINT::linear_depth(uv - float2(0.0,offset.y));
 
    float2 xymult = float2(abs(dmx - dpx), abs(dmy - dpy)) * sharpness;
    xymult = max(0.0, 1.0 - xymult);
       
    float ddx = (hmx - hpx) / (2.0 * offset.x) * xymult.x;
    float ddy = (hmy - hpy) / (2.0 * offset.y) * xymult.y;
   
    return normalize(float3(ddx, ddy, 1.0));
}
 
float3 blend_normals(float3 n1, float3 n2)
{
    //return normalize(float3(n1.xy*n2.z + n2.xy*n1.z, n1.z*n2.z));
    n1 += float3( 0, 0, 1);
    n2 *= float3(-1, -1, 1);
    return n1*dot(n1, n2)/n1.z - n2;
}

float bayer(float2 vpos, int max_level)
{
	float finalBayer   = 0.0;
	float finalDivisor = 0.0;
    float layerMult	   = 1.0;
    
  	for(float bayerLevel = max_level; bayerLevel >= 1.0; bayerLevel--)
	{
		layerMult 		   *= 4.0;

		float2 bayercoord 	= floor(vpos.xy * exp2(1 - bayerLevel)) % 2;
		float line0202 = bayercoord.x*2.0;

		finalBayer += lerp(line0202, 3.0 - line0202, bayercoord.y) / 3.0 * layerMult;
		finalDivisor += layerMult;
	}

	return finalBayer / finalDivisor;
}

/*=============================================================================
	Pixel Shaders
=============================================================================*/

struct Ray
{
	float3 origin;
	float3 dir;
	float  step;
	float3 pos;
};

struct SceneData
{
	float3 eyedir;
	float3 normal;
	float3 position;
	float  depth;
};

struct TraceData
{
	int num_steps;
	int num_refines;
	float2 uv;
	float3 error;
	bool hit;
};

struct BlurData
{
	float4 key;
	float4 mask;
};

void PS_PrepareColor(in SSR_VSOUT i, out float4 o : SV_Target0)
{
	o = tex2D(qUINT::sBackBufferTex, i.uv);
}
void PS_SSR(in SSR_VSOUT i, out float4 reflection : SV_Target0, out float4 blurbuffer : SV_Target1)
{
	blurbuffer 		= get_normal_and_edges_from_depth(i);
	float jitter 	= bayer(i.vpos.xy,3) - 0.5;

	SceneData scene;
	scene.position = get_position_from_uv(i.uv, i);
	scene.eyedir   = normalize(scene.position); //not the direction where the eye it but where it looks at
	scene.normal   = blend_normals(blurbuffer.xyz, get_normal_from_color(i.uv, 40.0 * qUINT::PIXEL_SIZE / scene.position.z * SSR_RELIEF_SCALE, 0.005 * SSR_RELIEF_AMOUNT, 1000.0));
	scene.depth    = scene.position.z / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;

	Ray ray;
	ray.origin = scene.position;
	ray.dir = reflect(scene.eyedir, scene.normal);
	ray.step = (0.2 + 0.05 * jitter * SSR_JITTER_AMOUNT) * sqrt(scene.depth);
	ray.pos = ray.origin + ray.dir * ray.step;

	TraceData trace;
	trace.uv = i.uv;
	trace.hit = 0;
	trace.num_steps = 20;
	trace.num_refines = 3;

	int j = 0;
	int k = 0;
	bool uv_inside_screen;

	while(j++ < trace.num_steps)
	{
		trace.uv =  get_uv_from_position(ray.pos, i);
		trace.error = get_position_from_uv(trace.uv, i) - ray.pos;

		if(trace.error.z < 0 && trace.error.z > -SSR_ACCEPT_RANGE * ray.step)
		{
			j = 0; //ensure we have enough steps left to complete our refinement

			if(k < trace.num_refines)
			{
				//step back	
				ray.step /= SSR_RAY_INC;
				ray.pos -= ray.dir * ray.step; 
				//decrease stepsize by magic amount - at some point the increased 
				//resolution is too small to notice and just adds up to the render cost
				ray.step *= SSR_RAY_INC * 0.05;
			}
			else
			{
				j += trace.num_steps; //algebraic "break" - much faster
				trace.hit = 1;	
			}
			k++;	
		}

		ray.pos += ray.dir * ray.step;
		ray.step *= SSR_RAY_INC;

		uv_inside_screen = all(saturate(-trace.uv.y * trace.uv.y + trace.uv.y));
		j += trace.num_steps * !uv_inside_screen;
	}

	float schlick = lerp(SSR_FRESNEL_K, 1, pow(1 - dot(-scene.eyedir, scene.normal), SSR_FRESNEL_EXP));
	float fade 	  = saturate(dot(scene.eyedir, ray.dir)) * saturate(1 - dot(-scene.eyedir, scene.normal));

	reflection.a   = trace.hit * schlick * fade;
	reflection.rgb = tex2D(sSSR_ColorTex, trace.uv).rgb * reflection.a;

	blurbuffer.xyz = blurbuffer.xyz * 0.5 + 0.5;
}


void spatial_blur_data(inout BlurData o, in sampler inputsampler, in float4 uv)
{
	o.key 	= tex2Dlod(inputsampler, uv);
	o.mask 	= tex2Dlod(qUINT::sCommonTex1, uv);
	o.mask.xyz = o.mask.xyz * 2 - 1;
}

float compute_spatial_tap_weight(in BlurData center, in BlurData tap)
{
	float depth_term = saturate(1 - abs(tap.mask.w - center.mask.w) * 50);
	float normal_term = saturate(dot(tap.mask.xyz, center.mask.xyz) * 50 - 49);
	return depth_term * normal_term;
}

float4 blur_filter(in SSR_VSOUT i, in sampler inputsampler, in float radius, in float2 axis)
{
	float4 blur_uv = float4(i.uv.xy, 0, 0);

    BlurData center, tap;
	spatial_blur_data(center, inputsampler, blur_uv);

	if(SSR_FILTER_SIZE == 0) return center.key;

	float kernel_size = radius;
	float k = -2.0 * rcp(kernel_size * kernel_size + 1e-3);

	float4 blursum 					= 0;
	float4 blursum_noweight 		= 0;
	float blursum_weight 			= 1e-3;
	float blursum_noweight_weight 	= 1e-3; //lel

	[loop]
	for(float j = -floor(kernel_size); j <= floor(kernel_size); j++)
	{
		spatial_blur_data(tap, inputsampler,  float4(i.uv + axis * (2.0 * j - 0.5), 0, 0));
		float tap_weight = compute_spatial_tap_weight(center, tap);

		blursum 			+= tap.key * tap_weight * exp(j * j * k) * tap.key.w;
		blursum_weight 		+= tap_weight * exp(j * j * k) * tap.key.w;
		blursum_noweight 			+= tap.key * exp(j * j * k) * tap.key.w;
		blursum_noweight_weight 	+= exp(j * j * k) * tap.key.w;
	}

	blursum /= blursum_weight;
	blursum_noweight /= blursum_noweight_weight;

	return lerp(center.key, blursum, saturate(blursum_weight * 2));
}

void PS_FilterH(in SSR_VSOUT i, out float4 o : SV_Target0)
{
	o = blur_filter(i, qUINT::sCommonTex0, SSR_FILTER_SIZE, float2(0, 1) * qUINT::PIXEL_SIZE);
}

void PS_FilterV(in SSR_VSOUT i, out float4 o : SV_Target0)
{
	float4 reflection = blur_filter(i, sSSR_ColorTex, SSR_FILTER_SIZE, float2(1, 0) * qUINT::PIXEL_SIZE);
	float alpha = reflection.w; //tex2D(qUINT::sCommonTex0, i.uv).w;

	float fade = saturate(1 - qUINT::linear_depth(i.uv) / SSR_FADE_DIST);
	o = tex2D(qUINT::sBackBufferTex, i.uv);

	o.rgb = lerp(o.rgb, reflection.rgb, alpha * fade);
}

/*=============================================================================
	Techniques
=============================================================================*/

technique SSR
{
	pass
	{
		VertexShader = VS_SSR;
		PixelShader  = PS_PrepareColor;
		RenderTarget = SSR_ColorTex;
	}
    pass
	{
		VertexShader = VS_SSR;
		PixelShader  = PS_SSR;
		RenderTarget0 = qUINT::CommonTex0;
		RenderTarget1 = qUINT::CommonTex1;
	}
	pass
	{
		VertexShader = VS_SSR;
		PixelShader  = PS_FilterH;
		RenderTarget = SSR_ColorTex;
	}
	pass
	{
		VertexShader = VS_SSR;
		PixelShader  = PS_FilterV;
	}
}