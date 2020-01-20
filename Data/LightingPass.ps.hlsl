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
__import AreaLightUtil;
__import Lights;
__import BRDF;

#define NumSamples 2048

cbuffer PerImageCB
{
    // G-Buffer
    // Lighting params
    LightData gDirLight;
    LightData gPointLight;
    LightData gAreaLight;
    float3 gAmbient;
    // Debug mode
    uint gDebugMode;

    float4 lightSamples[NumSamples];
};

// Debug modes
#define ShowPos         1
#define ShowNormals     2
#define ShowAlbedo      3
#define ShowLighting    4

ShadingResult evalMaterialAreaLight(ShadingData sd, LightData light)
{
    ShadingResult sr = initShadingResult();

    // Do Lighting for every Sample
    for (int i = 0; i < NumSamples; i++)
    {
        LightSample ls;
        ls.posW = mul(lightSamples[i], light.transMat).xyz;
        ls.L = ls.posW - sd.posW;
        float distSquared = dot(ls.L, ls.L);
        ls.distance = (distSquared > 1e-5f) ? length(ls.L) : 0;
        ls.L = (distSquared > 1e-5f) ? normalize(ls.L) : 0;

        // Calculate the falloff
        float cosTheta = -dot(ls.L, light.dirW); // cos of angle of light orientation
        float falloff = max(0.f, cosTheta) * light.surfaceArea;
        falloff *= getDistanceFalloff(distSquared);
        ls.diffuse = falloff * light.intensity;
        ls.specular = ls.diffuse;
        calcCommonLightProperties(sd, ls);

        // If the light doesn't hit the surface or we are viewing the surface from the back, return
        if (ls.NdotL <= 0) continue;
        sd.NdotV = saturate(sd.NdotV);

        // Calculate the diffuse term
        sr.diffuseBrdf = saturate(evalDiffuseBrdf(sd, ls));
        sr.diffuse += ls.diffuse * sr.diffuseBrdf * ls.NdotL;

        // Calculate the specular term
        sr.specularBrdf = saturate(evalSpecularBrdf(sd, ls));
        sr.specular += ls.specular * sr.specularBrdf * ls.NdotL;
    }
    sr.diffuse = sr.diffuse / (float)NumSamples; 
    sr.specular = sr.specular / (float)NumSamples;

    return sr;
};

float3 shade(float3 posW, float3 normalW, float linearRoughness, float4 albedo)
{

    // Discard empty pixels
    if (albedo.a <= 0)
    {
        discard;
    }

    /* Reconstruct the hit-point */
    ShadingData sd = initShadingData();
    sd.posW = posW;
    sd.V = normalize(gCamera.posW - posW);
    sd.N = normalW;
    sd.NdotV = abs(dot(sd.V, sd.N));
    sd.linearRoughness = linearRoughness;

    /* Reconstruct layers (diffuse and specular layer) */
    sd.diffuse = albedo.rgb;
    sd.opacity = 0;

    sd.specular = 0.28f;
    sd.roughness = 0.1f;

    float3 result;

    /* Do lighting */
    ShadingResult dirResult = evalMaterial(sd, gDirLight, 1);
    ShadingResult pointResult = evalMaterial(sd, gPointLight, 1);
    ShadingResult areaResult = evalMaterialAreaLight(sd, gAreaLight);

    // Debug vis
    if (gDebugMode == ShowPos)
        result = posW;
    else if (gDebugMode == ShowNormals)
        result = 0.5 * normalW + 0.5f;
    else if (gDebugMode == ShowAlbedo)
        result = albedo.rgb;
    else if (gDebugMode == ShowLighting)
        result = (dirResult.diffuseBrdf + pointResult.diffuseBrdf + areaResult.diffuseBrdf) / sd.diffuse.rgb;
    else
        result = dirResult.diffuse + dirResult.specular + pointResult.diffuse + pointResult.specular + areaResult.diffuse + areaResult.specular;

    return result;
}

Texture2D gGBuf0;
Texture2D gGBuf1;
Texture2D gGBuf2;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_POSITION) : SV_TARGET
{
    // Fetch a G-Buffer
    float3 posW    = gGBuf0.Load(int3(pos.xy, 0)).rgb;
    float4 buf1Val = gGBuf1.Load(int3(pos.xy, 0));
    float3 normalW = buf1Val.rgb;
    float linearRoughness = buf1Val.a;
    float4 albedo  = gGBuf2.Load(int3(pos.xy, 0));

    float3 color = shade(posW, normalW, linearRoughness, albedo);

    return float4(color, 1);
}
