/***************************************************************************
# Copyright (c) 2015, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************************************************************************/

__import ShaderCommon;
__import Shading;
__import LTC;
__import LTSH;
__import LTSHn2;
__import Lights;
__import BRDF;

#define NumSamples 4096
#define SampleReductionFactor 16
#define NumVertices 4

cbuffer PerImageCB
{
    // G-Buffer
    // Camera position
    float3 gCamPosW;

    // Lighting params
    LightData gDirLight;
    LightData gPointLight;
    LightData gAreaLight;
    float3 gAmbient;

    // state
    uint gDebugMode;
    uint gAreaLightRenderMode;

    // Vertices of the area light polygon
    float4 gAreaLightPosW[NumVertices];

    // Pseudo random seed from CPU
    float gSeed;
};

cbuffer SampleCB0 { float4 lightSamples0[NumSamples]; };
cbuffer SampleCB1 { float4 lightSamples1[NumSamples]; };
cbuffer SampleCB2 { float4 lightSamples2[NumSamples]; };
cbuffer SampleCB3 { float4 lightSamples3[NumSamples]; };

SamplerState gSampler;
Texture2D<float4> gLtcMinv;
Texture2D<float4> gLtshMinv;
Texture2D<float4> gLtshMinvN2;
Texture2D<float> gLtcCoeff;
Texture2D<float4> gLtshCoeff;
Texture2D<float4> gLtshCoeffN2;

// Debug modes
#define ShowPos         1
#define ShowNormals     2
#define ShowAlbedo      3
#define ShowLighting    4
#define ShowDiffuse     5
#define ShowSpecular    6

// Render modes
#define GroundTruth     0
#define LTC             1
#define LTSH            2
#define None            3
#define LtcBrdf         4
#define LtshBrdf        5
#define LTSH_N2         6

// for unbiased texture access
static const float m = 63.f / 64.f;
static const float b = .5f / 64.f;

// returns a random float in [0,1] based on a 2d point (texC)
// taken from Golden Noise: https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl
float rand(in float2 uv)
{
    float noiseX = (frac(sin(dot(uv, float2(12.9898, 78.233) * 2.0)) * 43758.5453));
    return noiseX;
}

// converts view direction and roughness to two floats in [0,63] to fetch the correct transformation matrix
float2 cos_theta_roughness_to_uv(float cosTheta, float roughness)
{
    float l_idx = acos(cosTheta) / 1.57079;
    float a_idx = sqrt(roughness);
    return float2(l_idx, a_idx);
}

// Dithering
// randomly rounds up or down a float2 
// the probability corresponds to how close the input float is to the closest integers
// 1.3 -> 1 with 70% and -> 2 with 30% probability
int2 dither(float2 uv, float2 texC) 
{
    int2 view_alpha = int2(floor(uv));

    float view_frac = frac(uv.x - view_alpha.x);
    float alpha_frac = frac(uv.y - view_alpha.y);

    float view_rand = rand(texC);
    float alpha_rand = rand(1 - texC);

    if (view_rand < view_frac) view_alpha.x += 1;
    if (alpha_rand < alpha_frac) view_alpha.y += 1;
    return view_alpha;
}

// normally lightPosW is stored in the LightData but for our ground truth sampling we need to set manually
LightSample calculateAreaLightSample(inout ShadingData sd, in LightData light, in float3 lightPosW)
{
    LightSample ls;

    ls.posW = lightPosW;

    ls.L = ls.posW - sd.posW;
    float distSquared = dot(ls.L, ls.L);
    ls.distance = (distSquared > 1e-5f) ? length(ls.L) : 0;
    ls.L = (distSquared > 1e-5f) ? normalize(ls.L) : 0;

    // Calculate the falloff
    float cosTheta = -dot(ls.L, light.dirW); // cos of angle of light orientation
    float falloff = max(0.f, cosTheta);
    falloff *= getDistanceFalloff(distSquared);
    // calculate falloff for other direction to enable lighting in both directions
    if (falloff < 1e-5f)
    {
        cosTheta = -dot(ls.L, -light.dirW); // cos of angle of light orientation
        falloff = max(0.f, cosTheta);
        falloff *= getDistanceFalloff(distSquared);
    }

    ls.diffuse = falloff;
    ls.specular = falloff;
    calcCommonLightProperties(sd, ls);
    return ls;
}


float3 evalDiffuseAreaLight(ShadingData sd, LightData light) {
    // diffuse lighting
    float3x3 Identity = float3x3(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
        );

    return LTC_Evaluate(sd.N, sd.V, sd.posW, Identity, gAreaLightPosW, true, light.intensity) * sd.diffuse / 2.0 / 3.14159;
}


ShadingResult evalMaterialAreaLightLTC(ShadingData sd, LightData light, float3 specularColor)
{
    ShadingResult sr = initShadingResult();

    sr.diffuse = evalDiffuseAreaLight(sd, light);

    float2 uv = cos_theta_roughness_to_uv(sd.NdotV, sd.roughness);

    // unbiased access
    uv = m * uv + b;

    float3x3 MInv = getLtcMatrix(uv);
    float coeff = getCoeff(uv);

    sr.specular = LTC_Evaluate(sd.N, sd.V, sd.posW, MInv, gAreaLightPosW, true, light.intensity) * specularColor * coeff;
    // Normalization
    sr.specular /= 2 * 3.14159;

    sr.color.rgb = sr.diffuse + sr.specular;
    return sr;
}

ShadingResult evalMaterialAreaLightLTSH(ShadingData sd, LightData light, float3 specularColor, float2 texC)
{
    ShadingResult sr = initShadingResult();

    sr.diffuse = evalDiffuseAreaLight(sd, light);

    float2 uv = cos_theta_roughness_to_uv(sd.NdotV, sd.roughness);
    // translate from [0,1] to [0,63]
    uv *= 63.f;

    int2 view_alpha = dither(uv, texC);

    // specular lighting
    float3x3 MInv = getLtshMatrix(view_alpha);
    
    // construct orthonormal basis around N
    float3 T1, T2;
    T1 = normalize(sd.V - sd.N * sd.NdotV);
    T2 = cross(sd.N, T1);

    // rotate area light in (T1, T2, R) basis
    float3x3 baseMat = float3x3(T1, T2, sd.N);

    float3 L[5];
    L[0] = mul(baseMat, gAreaLightPosW[0].xyz - sd.posW);
    L[1] = mul(baseMat, gAreaLightPosW[1].xyz - sd.posW);
    L[2] = mul(baseMat, gAreaLightPosW[2].xyz - sd.posW);
    L[3] = mul(baseMat, gAreaLightPosW[3].xyz - sd.posW);
    L[4] = L[3];

    int n = 4;
    ClipQuadToHorizon(L, n);

    float result = 0;

    if (n != 0) {
        L[0] = normalize(mul(MInv, L[0]));
        L[1] = normalize(mul(MInv, L[1]));
        L[2] = normalize(mul(MInv, L[2]));
        L[3] = normalize(mul(MInv, L[3]));
        L[4] = normalize(mul(MInv, L[4]));

        float Lc[25];
        polygonSH(L, n, Lc);

        float coeffs[25];
        getLtshCoeffs(view_alpha, coeffs);
        for (int i = 0; i < 25; i++)
        {
            result += Lc[i] * coeffs[i];
        }
    }

    sr.specular = abs(result) * light.intensity * specularColor;
    sr.color.rgb = sr.diffuse + sr.specular;
    return sr;
}

ShadingResult evalMaterialAreaLightLTSH_N2(ShadingData sd, LightData light, float3 specularColor, float2 texC)
{
    ShadingResult sr = initShadingResult();

    sr.diffuse = evalDiffuseAreaLight(sd, light);

    float2 uv = cos_theta_roughness_to_uv(sd.NdotV, sd.roughness);
    // translate from [0,1] to [0,63]
    uv *= 63.f;

    int2 view_alpha = dither(uv, texC);

    // specular lighting
    float3x3 MInv = getLtshMatrixN2(view_alpha);

    // construct orthonormal basis around N
    float3 T1, T2;
    T1 = normalize(sd.V - sd.N * sd.NdotV);
    T2 = cross(sd.N, T1);

    // rotate area light in (T1, T2, R) basis
    float3x3 baseMat = float3x3(T1, T2, sd.N);

    float3 L[5];
    L[0] = mul(baseMat, gAreaLightPosW[0].xyz - sd.posW);
    L[1] = mul(baseMat, gAreaLightPosW[1].xyz - sd.posW);
    L[2] = mul(baseMat, gAreaLightPosW[2].xyz - sd.posW);
    L[3] = mul(baseMat, gAreaLightPosW[3].xyz - sd.posW);
    L[4] = L[3];

    int n = 4;
    ClipQuadToHorizon(L, n);

    float result = 0;

    if (n != 0) {
        L[0] = normalize(mul(MInv, L[0]));
        L[1] = normalize(mul(MInv, L[1]));
        L[2] = normalize(mul(MInv, L[2]));
        L[3] = normalize(mul(MInv, L[3]));
        L[4] = normalize(mul(MInv, L[4]));

        float Lc[9];
        polygonSHN2(L, n, Lc);

        float coeffs[9];
        getLtshCoeffsN2(view_alpha, coeffs);
        for (int i = 0; i < 9; i++)
        {
            result += Lc[i] * coeffs[i];
        }
    }

    sr.specular = abs(result) * light.intensity * specularColor;
    sr.color.rgb = sr.diffuse + sr.specular;
    return sr;
}

ShadingResult evalMaterialAreaLightGroundTruth(ShadingData sd, LightData light, float3 specularColor, float2 texC)
{
    ShadingResult sr = initShadingResult();

    float2 uv = cos_theta_roughness_to_uv(sd.NdotV, sd.roughness);

    // unbiased access
    float2 cos_uv = m * uv + b;

    uv *= 63.f;

    int2 view_alpha = dither(uv, texC);

    float3x3 MInv_cos = getLtcMatrix(cos_uv);
    float3x3 MInv_sh = getLtshMatrix(view_alpha);

    float ltshCoeffs[25];
    getLtshCoeffs(view_alpha, ltshCoeffs);
    float cosCoeff = getCoeff(cos_uv);

    float3 T1, T2;
    T1 = normalize(sd.V - sd.N * sd.NdotV);
    T2 = cross(sd.N, T1);

    // rotate area light in (T1, T2, R) basis
    float3x3 baseMat = float3x3(T1, T2, sd.N);
    MInv_cos = mul(MInv_cos, baseMat);
    MInv_sh = mul(MInv_sh, baseMat);

    // decide, which set of point lights to sample
    int sampleSet = round(rand(texC) * 4);

    // Do Lighting for every Sample
    for (int i = 0; i < NumSamples / SampleReductionFactor; i++)
    {
        float3 lightPosW;
        // use different sample set dependent on random value
        if (sampleSet == 0)
            lightPosW = lightSamples0[i].xyz;
        else if (sampleSet == 1)
            lightPosW = lightSamples1[i].xyz;
        else if (sampleSet == 2)
            lightPosW = lightSamples2[i].xyz;
        else
            lightPosW = lightSamples3[i].xyz;

        LightSample ls = calculateAreaLightSample(sd, light, lightPosW);

        // If the light doesn't hit the surface or we are viewing the surface from the back, return
        if (ls.NdotL <= 0) continue;
        sd.NdotV = saturate(sd.NdotV);

        // Calculate the diffuse term
        sr.diffuseBrdf = evalDiffuseLambertBrdf(sd, ls);
        sr.diffuse += ls.diffuse * sr.diffuseBrdf * ls.NdotL;

        // Calculate the specular term
        if (gAreaLightRenderMode == LtcBrdf)            sr.specularBrdf = evalLtcBrdf(sd, ls, MInv_cos) * cosCoeff;
        else if (gAreaLightRenderMode == LtshBrdf)      sr.specularBrdf = evalLtshBrdf(sd, ls, MInv_sh, ltshCoeffs);
        else if (gAreaLightRenderMode == GroundTruth)   sr.specularBrdf = evalSpecularBrdf(sd, ls) * ls.NdotL;
        sr.specular += ls.specular * sr.specularBrdf;
    }
    sr.diffuse = sr.diffuse * SampleReductionFactor / (float)NumSamples * light.surfaceArea * light.intensity;
    sr.specular = sr.specular * SampleReductionFactor / (float)NumSamples * light.surfaceArea * light.intensity * specularColor;
    sr.color.rgb = sr.diffuse + sr.specular;

    return sr;
};

float3 shade(float3 posW, float3 normalW, float linearRoughness, float4 albedo, float3 specular, float roughness, float2 texC)
{
    // Discard empty pixels
    if (albedo.a <= 0)
    {
        discard;
    }

    /* Reconstruct the hit-point */
    ShadingData sd = initShadingData();
    sd.posW = posW;
    sd.V = normalize(gCamPosW - posW);
    sd.N = normalW;
    sd.NdotV = abs(dot(sd.V, sd.N));
    sd.linearRoughness = linearRoughness;

    /* Reconstruct layers (diffuse and specular layer) */
    sd.diffuse = albedo.rgb;
    sd.opacity = 0;

    // sd.specular is used as F0 in BRDF.slang and needs to be fixed for our technique
    sd.specular = .4f;
    sd.roughness = max(roughness, .1f);

    /* Do lighting */
    ShadingResult dirResult = evalMaterial(sd, gDirLight, 1);
    ShadingResult pointResult = evalMaterial(sd, gPointLight, 1);
    ShadingResult areaResult;
    if (gAreaLightRenderMode == GroundTruth || gAreaLightRenderMode == LtcBrdf || gAreaLightRenderMode == LtshBrdf)
        areaResult = evalMaterialAreaLightGroundTruth(sd, gAreaLight, specular, texC);
    else if (gAreaLightRenderMode == LTC)
        areaResult = evalMaterialAreaLightLTC(sd, gAreaLight, specular);
    else if (gAreaLightRenderMode == LTSH)
        areaResult = evalMaterialAreaLightLTSH(sd, gAreaLight, specular, texC);
    else if (gAreaLightRenderMode == LTSH_N2)
        areaResult = evalMaterialAreaLightLTSH_N2(sd, gAreaLight, specular, texC);
    else if (gAreaLightRenderMode == None)
        areaResult = initShadingResult();

    float3 result;

    // Debug vis
    if (gDebugMode == ShowPos)
        result = posW;
    else if (gDebugMode == ShowNormals)
        result = 0.5 * normalW + 0.5f;
    else if (gDebugMode == ShowAlbedo)
        result = albedo.rgb;
    else if (gDebugMode == ShowLighting)
        result = (dirResult.diffuseBrdf + pointResult.diffuseBrdf + areaResult.diffuseBrdf) / sd.diffuse.rgb;
    else if (gDebugMode == ShowDiffuse)
        result = dirResult.diffuse + pointResult.diffuse + areaResult.diffuse;
    else if (gDebugMode == ShowSpecular)
        result = dirResult.specular + pointResult.specular + areaResult.specular;
    else
        result = dirResult.diffuse + dirResult.specular * specular + pointResult.diffuse + pointResult.specular * specular + areaResult.color.rgb;

    return result;
}

Texture2D gGBuf0;
Texture2D gGBuf1;
Texture2D gGBuf2;
Texture2D gGBuf3;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_POSITION) : SV_TARGET
{
    // Fetch a G-Buffer
    float4 buf0Val = gGBuf0.Load(int3(pos.xy, 0));
    float3 posW    = buf0Val.rgb;
    float lightFlag = buf0Val.a;
    float4 buf1Val = gGBuf1.Load(int3(pos.xy, 0));
    float3 normalW = buf1Val.rgb;
    float linearRoughness = buf1Val.a;
    float4 albedo  = gGBuf2.Load(int3(pos.xy, 0));

    float4 buf3Val = gGBuf3.Load(int3(pos.xy, 0));
    float3 specular = buf3Val.rgb;
    float roughness = buf3Val.a;

    if (lightFlag > .5f) 
    {
        float maxIntensity = max(max(gAreaLight.intensity.r, gAreaLight.intensity.g), gAreaLight.intensity.b);
        return float4(gAreaLight.intensity / maxIntensity, 1);
    };

    float3 color = shade(posW, normalW, linearRoughness, albedo, specular, roughness, texC);

    return float4(color, 1);
}
