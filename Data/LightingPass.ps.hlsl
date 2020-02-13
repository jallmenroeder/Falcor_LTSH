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
    // Debug mode
    uint gDebugMode;
    // Area light render mode
    uint gAreaLightRenderMode;
    float4 gAreaLightPosW[NumVertices];
};

cbuffer SampleCB0 { float4 lightSamples0[NumSamples]; };
cbuffer SampleCB1 { float4 lightSamples1[NumSamples]; };
cbuffer SampleCB2 { float4 lightSamples2[NumSamples]; };
cbuffer SampleCB3 { float4 lightSamples3[NumSamples]; };

SamplerState gSampler;
Texture2D<float4> gMinv;
Texture2D<float> gLtcCoeff;
Texture2D<float4> gLtshCoeff;
Texture1D<float4> gLegendre2345;

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

// returns a random int in {0, 1, 2, 3} based on a 2d point (texC)
int rand(float2 co)
{
    return (int)(frac(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453123) * 4);
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

ShadingResult evalMaterialAreaLightLTC(ShadingData sd, LightData light, float3 specularColor)
{
    ShadingResult sr = initShadingResult();

    // diffuse lighting
    float3x3 Identity = float3x3(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
        );

    sr.diffuse = LTC_Evaluate(sd.N, sd.V, sd.posW, Identity, gAreaLightPosW, true, light.intensity) * sd.diffuse;

    // normalize
    sr.diffuse /= 2 * 3.14159;

    float3x3 MInv = getMatrix(sd.NdotV, sd.roughness);
    float coeff = getCoeff(sd.NdotV, sd.roughness);

    sr.specular = LTC_Evaluate(sd.N, sd.V, sd.posW, MInv, gAreaLightPosW, true, light.intensity) * specularColor * coeff;
    // Normalization, TODO: check if this is correct
    sr.specular /= 2 * 3.14159;

    sr.color.rgb = sr.diffuse + sr.specular;
    return sr;
}

ShadingResult evalMaterialAreaLightLTSH(ShadingData sd, LightData light, float3 specularColor)
{
    ShadingResult sr = initShadingResult();

    // diffuse lighting
    float3x3 Identity = float3x3(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
        );

    sr.diffuse = LTC_Evaluate(sd.N, sd.V, sd.posW, Identity, gAreaLightPosW, true, light.intensity) * sd.diffuse;

    // normalize
    sr.diffuse /= 2 * 3.14159;
    sr.diffuse = sr.diffuse;

    // specular lighting
    int l_idx = round(acos(sd.NdotV) * 64 / 1.57079);
    int a_idx = round(sqrt(sd.roughness) * 64);

    float3x3 MInv = getMatrix(sd.NdotV, sd.roughness);
    
    // construct orthonormal basis around N
    float3 T1, T2;
    T1 = normalize(sd.V - sd.N * sd.NdotV);
    T2 = cross(sd.N, T1);

    // rotate area light in (T1, T2, R) basis
    float3x3 baseMat = float3x3(T1, T2, sd.N);
    MInv = mul(MInv, baseMat);

    float3 lightPos[5];
    lightPos[0] = normalize(mul(MInv, gAreaLightPosW[0].xyz - sd.posW));
    lightPos[1] = normalize(mul(MInv, gAreaLightPosW[1].xyz - sd.posW));
    lightPos[2] = normalize(mul(MInv, gAreaLightPosW[2].xyz - sd.posW));
    lightPos[3] = normalize(mul(MInv, gAreaLightPosW[3].xyz - sd.posW));

    float Lc[25];
    polygonSH(lightPos, 4, Lc);

    float cArea = get_transfer_color(Lc, int2(l_idx, a_idx));

    sr.specular = cArea * light.intensity * specularColor;
    sr.color.rgb = sr.diffuse + sr.specular;
    return sr;
}

ShadingResult evalMaterialAreaLightGroundTruth(ShadingData sd, LightData light, float3 specularColor, int sampleSet)
{
    ShadingResult sr = initShadingResult();

    float3x3 MInv = getMatrix(sd.NdotV, sd.roughness);
    float coeff = getCoeff(sd.NdotV, sd.roughness);
    float3 T1, T2;
    T1 = normalize(sd.V - sd.N * sd.NdotV);
    T2 = cross(sd.N, T1);

    // rotate area light in (T1, T2, R) basis
    float3x3 baseMat = float3x3(T1, T2, sd.N);
    MInv = mul(MInv, baseMat);

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
        sr.specularBrdf = evalLtcBrdf(sd, ls, MInv);
        sr.specular += ls.specular * sr.specularBrdf * coeff;
    }
    sr.diffuse = sr.diffuse * SampleReductionFactor / (float)NumSamples * light.surfaceArea * light.intensity;
    sr.specular = sr.specular * SampleReductionFactor / (float)NumSamples * light.surfaceArea * light.intensity * specularColor;
    // sr.specular /= 3.14159;
    sr.color.rgb = sr.diffuse + sr.specular;

    return sr;
};

float3 shade(float3 posW, float3 normalW, float linearRoughness, float4 albedo, float3 specular, float roughness, int sampleSet)
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

    // sd.specular is used as F0 in BRDF.slang and needs to be fixed four our technique
    sd.specular = .4f;
    sd.roughness = roughness;

    /* Do lighting */
    ShadingResult dirResult = evalMaterial(sd, gDirLight, 1);
    ShadingResult pointResult = evalMaterial(sd, gPointLight, 1);
    ShadingResult areaResult;
    if (gAreaLightRenderMode == GroundTruth)
        areaResult = evalMaterialAreaLightGroundTruth(sd, gAreaLight, specular, sampleSet);
    else if (gAreaLightRenderMode == LTC)
        areaResult = evalMaterialAreaLightLTC(sd, gAreaLight, specular);
    else if (gAreaLightRenderMode == LTSH)
        // not implemented yet
        areaResult = evalMaterialAreaLightLTSH(sd, gAreaLight, specular);
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

    int sampleSet = rand(texC);
    float3 color = shade(posW, normalW, linearRoughness, albedo, specular, roughness, sampleSet);

    return float4(color, 1);
}
