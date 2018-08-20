/*=============================================================================

	ReShade 3 effect file
        visit facebook.com/MartyMcModding for news/updates

        Smart Depth of Field
        by Marty McFly / P.Gilcher
        part of qUINT shader library for ReShade 3

        CC BY-NC-ND 3.0 licensed.

=============================================================================*/

/*=============================================================================
	Preprocessor settings
=============================================================================*/

#define THRESH_FULL_TO_HALF			(QUALITY_BIAS * 6)		//at what blur radius in pixels the DOF jumps from fullres blur to halfres blur (gridsize 1x1 -> 2x2)
#define THRESH_HALF_TO_QUART		(QUALITY_BIAS * 16)		//at what blur radius in pixels the DOF jumps from halfres blur to 1/4 res blur (gridsize 2x2 -> 4x4)
#define THRESH_QUART_TO_EIGHTH		(QUALITY_BIAS * 64)		//at what blur radius in pixels the DOF jumps from 1/4 res blur to 1/8 res blur (gridsize 4x4 -> 8x8)
#define THRESH_EIGHTH_TO_16TH		(QUALITY_BIAS * 128)	//at what blur radius in pixels the DOF jumps from 1/8 res blur to 1/16 res blur (gridsize 8x8 -> 16x16)
#define THRESH_16TH_TO_32TH			(QUALITY_BIAS * 256)	//at what blur radius in pixels the DOF jumps from 1/16 res blur to 1/32 res blur (gridsize 16x16 -> 32x32)

#define THRESH_PADDING_PERCENT				20.0	//padding works like this: lower level renders to 100%+padding, next level renders starting from 100%-padding, so there#s some overlap to make transitions smooth

#define THRESH_PADDING_LOWER				(0.01 * (100.0 - THRESH_PADDING_PERCENT))
#define THRESH_PADDING_UPPER				(0.01 * (100.0 + THRESH_PADDING_PERCENT))

//DO NOT CHANGE
#define TILE_SIZE_FULL 		1
#define TILE_SIZE_HALF 		2
#define TILE_SIZE_QUARTER 	4
#define TILE_SIZE_EIGHTH	8
#define TILE_SIZE_16TH		16
#define TILE_SIZE_32TH		32

/*=============================================================================
	UI Uniforms
=============================================================================*/


uniform float FOCUS_PLANE_DEPTH <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.1;

uniform float NEAR_BLUR_CURVE <
    ui_type = "drag";
    ui_min = 0.5;
    ui_max = 6.0;
> = 1.0;

uniform float FAR_BLUR_CURVE <
    ui_type = "drag";
    ui_min = 0.5;
    ui_max = 6.0;
> = 1.0;

uniform float HYPERFOCAL_DEPTH <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 1.0;
> = 1.0;

uniform float MAX_BLUR_RADIUS <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 400.0;
> = 10.0;

uniform float QUALITY_BIAS <
    ui_type = "drag";
    ui_min = 0.5;
    ui_max = 2.0;
> = 1.0;

uniform float test <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 100.0;
> = 5.0;

uniform float test2 <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 100.0;
> = 20.0;

uniform float test3 <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 100.0;
> = 60.0;

uniform float test4 <
    ui_type = "drag";
    ui_min = 0.0;
    ui_max = 100.0;
> = 2.0;
/*=============================================================================
	Textures, Samplers, Globals
=============================================================================*/

#define INF	4096

#include "qUINT_common.fxh"

texture DofLutCA < source = "qUINT_doflutca.png"; > { Width = 512; Height = 256; Format = RGBA8; };
sampler2D sDofLutCA	{ Texture = DofLutCA;	};
texture DofLutSDF < source = "qUINT_dofsdflut.png"; > { Width = 128; Height = 128; Format = RGBA8; };
sampler2D sDofLutSDF	{ Texture = DofLutSDF;	};

texture2D OriginalColorTex 	{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA8; 	MipLevels = 3;};
sampler2D sOriginalColorTex	{ Texture = OriginalColorTex;	};

/*=============================================================================
	Vertex Shader
=============================================================================*/

struct VSOUT
{
	float4   vpos : SV_Position;
    float2   uv   : TEXCOORD0;
};

VSOUT VS_DOF(in uint id : SV_VertexID)
{
    VSOUT o;
    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;
    o.vpos = float4(o.uv.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return o;
}

/*=============================================================================
	Functions
=============================================================================*/

float linear_depth_area(float2 uv)
{
	float3 ddxy = float3(qUINT::PIXEL_SIZE, 0);

	float d[5] = 
	{	
		qUINT::linear_depth(uv),
		qUINT::linear_depth(uv - ddxy.xz), 	qUINT::linear_depth(uv + ddxy.xz), 
        qUINT::linear_depth(uv - ddxy.zy), 	qUINT::linear_depth(uv + ddxy.zy)
	};

	float min_d = min(min(min(d[0],d[1]),min(d[2],d[3])),d[4]);
	return lerp(min_d, d[0], 0.001);
}

/*=============================================================================
	Pixel Shaders
=============================================================================*/

void PS_COC(in VSOUT i, out float4 o : SV_Target0)
{
	float d = linear_depth_area(i.uv);
    float f = FOCUS_PLANE_DEPTH;
    float h = HYPERFOCAL_DEPTH;
    float near_c = NEAR_BLUR_CURVE;
    float far_c = FAR_BLUR_CURVE;

    f = saturate(f / h);
    d = saturate(d / h);

    float coc;

    [branch]
	if(d < f)
	{
		coc = ldexp(d / f - 1, -0.5 * near_c * near_c);
	}
	else
	{
		coc = (d - f) / (ldexp(f, far_c * far_c) - f);	    
	}

	o.w = saturate(coc * 0.5 + 0.5);
	o.rgb = tex2D(qUINT::sBackBufferTex, i.uv).rgb;
}

float3 sdf_blur(in VSOUT i, in float signed_coc, in float GRID_SIZE, in int TILE_SIZE)
{
	float3 o = 0;
	float3 ca_weight = 0;

	float2 pos_in_tile 		= i.vpos.xy % TILE_SIZE;
	float2 pos_in_tile_ndc 	= pos_in_tile - TILE_SIZE * 0.5;

	float grid_half_dim = (GRID_SIZE + 0.5) * TILE_SIZE;
	float grid_bounds = ceil(GRID_SIZE/2);

	float4 offset_2_uv;
	offset_2_uv.xy = rcp(2 * grid_bounds * TILE_SIZE);
	offset_2_uv.zw = 0.5;

	[loop]for(int x = -grid_bounds; x <= grid_bounds; x++)
	[loop]for(int y = -grid_bounds; y <= grid_bounds; y++)
	{
		float2 current_offset = float2(x, y) * TILE_SIZE - pos_in_tile_ndc; 
		float current_radius = sqrt(dot(current_offset, current_offset));

		float shape_sdf = tex2Dlod(sDofLutSDF, float4(current_offset * offset_2_uv.xy + offset_2_uv.zw, 0, 0)).x;
		float3 shape_ca = tex2Dlod(sDofLutCA, float4(1, shape_sdf, 0, 0)).rgb;
		float4 t = tex2Dfetch(sOriginalColorTex, int4(i.vpos.xy + current_offset, 0, 0));

		float alpha = saturate((abs(t.w * 2 - 1) * MAX_BLUR_RADIUS + grid_bounds * shape_sdf - grid_bounds * 1.41421356) * shape_sdf);

		o     	  += pow(t.rgb, 8) * shape_ca * alpha;
		ca_weight += 				 shape_ca * alpha;
	}
	o /= ca_weight;
	o = pow(o, 1./8.0);

	return o;
}

void PS_PrepareGridAndCoC(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlodoffset(sOriginalColorTex, float4(i.uv,0,0), int2(0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	int TILE_SIZE = 1;
	if(GRID_SIZE > THRESH_FULL_TO_HALF  * THRESH_PADDING_LOWER) TILE_SIZE = 2;
	if(GRID_SIZE > THRESH_HALF_TO_QUART * THRESH_PADDING_LOWER) TILE_SIZE = 4;
	if(GRID_SIZE > THRESH_QUART_TO_EIGHTH  * THRESH_PADDING_LOWER) TILE_SIZE = 8;	
	if(GRID_SIZE > THRESH_EIGHTH_TO_16TH  * THRESH_PADDING_LOWER) TILE_SIZE = 16;	
}

void PS_BatchBlur(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlod(sOriginalColorTex, float4(i.uv,0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	o = tex2D(qUINT::sBackBufferTex, i.uv);

	[branch]
	if(GRID_SIZE < THRESH_FULL_TO_HALF * THRESH_PADDING_UPPER && GRID_SIZE > THRESH_FULL_TO_HALF * THRESH_PADDING_LOWER)
		o.rgb = lerp(
			o.rgb, 
			sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_FULL, TILE_SIZE_FULL), 
			smoothstep(THRESH_FULL_TO_HALF * THRESH_PADDING_LOWER, THRESH_FULL_TO_HALF * THRESH_PADDING_UPPER, GRID_SIZE));

	[branch]
	if(GRID_SIZE > THRESH_FULL_TO_HALF * THRESH_PADDING_LOWER && GRID_SIZE < THRESH_HALF_TO_QUART * THRESH_PADDING_UPPER) 
		o.rgb = lerp(
			o.rgb, 
			sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_HALF, TILE_SIZE_HALF), 
			smoothstep(THRESH_FULL_TO_HALF * THRESH_PADDING_LOWER, THRESH_FULL_TO_HALF * THRESH_PADDING_UPPER, GRID_SIZE));	

	[branch]
	if(GRID_SIZE > THRESH_HALF_TO_QUART * THRESH_PADDING_LOWER && GRID_SIZE < THRESH_QUART_TO_EIGHTH * THRESH_PADDING_UPPER)  
		o.rgb = lerp(
			o.rgb, 
			sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_QUARTER, TILE_SIZE_QUARTER), 
			smoothstep(THRESH_HALF_TO_QUART * THRESH_PADDING_LOWER, THRESH_HALF_TO_QUART * THRESH_PADDING_UPPER, GRID_SIZE));

	[branch]
	if(GRID_SIZE > THRESH_QUART_TO_EIGHTH * THRESH_PADDING_LOWER && GRID_SIZE < THRESH_EIGHTH_TO_16TH * THRESH_PADDING_UPPER) 
		o.rgb = lerp(
			o.rgb, 
			sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_EIGHTH, TILE_SIZE_EIGHTH), 
			smoothstep(THRESH_QUART_TO_EIGHTH * THRESH_PADDING_LOWER, THRESH_QUART_TO_EIGHTH * THRESH_PADDING_UPPER, GRID_SIZE));

	[branch]
	if(GRID_SIZE > THRESH_EIGHTH_TO_16TH * THRESH_PADDING_LOWER && GRID_SIZE < THRESH_16TH_TO_32TH * THRESH_PADDING_UPPER)
		o.rgb = lerp(
			o.rgb, 
			sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_16TH, TILE_SIZE_16TH), 
			smoothstep(THRESH_EIGHTH_TO_16TH * THRESH_PADDING_LOWER, THRESH_EIGHTH_TO_16TH * THRESH_PADDING_UPPER, GRID_SIZE));	

	[branch]
	if(GRID_SIZE > THRESH_16TH_TO_32TH * THRESH_PADDING_LOWER)
		o.rgb = lerp(
			o.rgb, 
			sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_32TH, TILE_SIZE_32TH), 
			smoothstep(THRESH_16TH_TO_32TH * THRESH_PADDING_LOWER, THRESH_16TH_TO_32TH * THRESH_PADDING_UPPER, GRID_SIZE));	
}

void PS_BlurLOD0(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlodoffset(sOriginalColorTex, float4(i.uv,0,0), int2(0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	o = 0;

	[branch]if(GRID_SIZE < THRESH_FULL_TO_HALF * THRESH_PADDING_UPPER) 
	o = sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_FULL, TILE_SIZE_FULL);

	o = lerp(tex2D(qUINT::sBackBufferTex, i.uv), o, smoothstep(1, THRESH_FULL_TO_HALF * THRESH_PADDING_LOWER, GRID_SIZE));	
}

void PS_BlurLOD1(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlodoffset(sOriginalColorTex, float4(i.uv,0,0), int2(0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	o = 0;

	[branch]if(GRID_SIZE > THRESH_FULL_TO_HALF  * THRESH_PADDING_LOWER
			&& GRID_SIZE < THRESH_HALF_TO_QUART * THRESH_PADDING_UPPER) 
	o = sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_HALF, TILE_SIZE_HALF);

	o = lerp(tex2D(qUINT::sBackBufferTex, i.uv), o, smoothstep(THRESH_FULL_TO_HALF * THRESH_PADDING_LOWER, THRESH_FULL_TO_HALF * THRESH_PADDING_UPPER, GRID_SIZE));	

}

void PS_BlurLOD2(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlodoffset(sOriginalColorTex, float4(i.uv,0,0), int2(0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	o = 0;

	[branch]if(GRID_SIZE > THRESH_HALF_TO_QUART * THRESH_PADDING_LOWER 
			&& GRID_SIZE < THRESH_QUART_TO_EIGHTH * THRESH_PADDING_UPPER) 
	o = sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_QUARTER, TILE_SIZE_QUARTER);

	o = lerp(tex2D(qUINT::sBackBufferTex, i.uv), o, smoothstep(THRESH_HALF_TO_QUART * THRESH_PADDING_LOWER, THRESH_HALF_TO_QUART * THRESH_PADDING_UPPER, GRID_SIZE));	

}

void PS_BlurLOD3(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlodoffset(sOriginalColorTex, float4(i.uv,0,0), int2(0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	o = 0;

	[branch]if(GRID_SIZE > THRESH_QUART_TO_EIGHTH * THRESH_PADDING_LOWER 
			&& GRID_SIZE < THRESH_EIGHTH_TO_16TH * THRESH_PADDING_UPPER) 
	o = sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_EIGHTH, TILE_SIZE_EIGHTH);

	o = lerp(tex2D(qUINT::sBackBufferTex, i.uv), o, smoothstep(THRESH_QUART_TO_EIGHTH * THRESH_PADDING_LOWER, THRESH_QUART_TO_EIGHTH * THRESH_PADDING_UPPER, GRID_SIZE));	
}



void PS_BlurLOD4(in VSOUT i, out float4 o : SV_Target0)
{
	o = tex2Dlodoffset(sOriginalColorTex, float4(i.uv,0,0), int2(0,0));

	float coc = abs(o.w * 2.0 - 1.0);
	float GRID_SIZE = ceil(coc * MAX_BLUR_RADIUS);

	o = 0;

	[branch]if(GRID_SIZE > THRESH_EIGHTH_TO_16TH * THRESH_PADDING_LOWER) 
	o = sdf_blur(i, o.w, GRID_SIZE / TILE_SIZE_16TH, TILE_SIZE_16TH);
	o = lerp(tex2D(qUINT::sBackBufferTex, i.uv), o, smoothstep(THRESH_EIGHTH_TO_16TH * THRESH_PADDING_LOWER, THRESH_EIGHTH_TO_16TH * THRESH_PADDING_UPPER, GRID_SIZE));	
}

/*=============================================================================
	Techniques
=============================================================================*/

technique DOF
{
    pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_COC;
        RenderTarget = OriginalColorTex;
	}
	pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_BatchBlur;
	}
	/*
	pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_BlurLOD0;
	}
	pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_BlurLOD1;
	}
	pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_BlurLOD2;
	}
	pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_BlurLOD3;
	}
	pass
	{
		VertexShader = VS_DOF;
		PixelShader  = PS_BlurLOD4;
	}*/
}