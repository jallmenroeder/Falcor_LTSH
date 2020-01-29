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
__import DefaultVS;
__import ShaderCommon;
__import Polygon;
__import Shading;

#define NUM_VERTICES 4

struct PsOut
{
    float4 fragColor0 : SV_TARGET0;
    float4 fragColor1 : SV_TARGET1;
    float4 fragColor2 : SV_TARGET2;
    float4 fragColor3 : SV_TARGET3;
};

cbuffer PolygonData
{
    float4x4 transMat;
    float4x4 transMatIT;
    float4 polygon[NUM_VERTICES];
};


bool isInside(float2 p)
{

    // Create a point for line segment from p to infinite 
    float2 extreme = float2(3.402823466e+38F, p.y);

    // Count intersections of the above line with sides of polygon 
    int count = 0, i = 0;
    do
    {
        int next = (i + 1) % NUM_VERTICES;

        // Check if the line segment from 'p' to 'extreme' intersects 
        // with the line segment from 'polygon[i]' to 'polygon[next]' 
        if (doIntersect(polygon[i].xy, polygon[next].xy, p, extreme))
        {
            // If the point 'p' is colinear with line segment 'i-next', 
            // then check if it lies on segment. If it lies, return true, 
            // otherwise false 
            if (orientation(polygon[i].xy, p, polygon[next].xy) == 0)
                return onSegment(polygon[i].xy, p, polygon[next].xy);

            count++;
        }
        i = next;
    } while (i != 0);

    // Return true if count is odd, false otherwise 
    return count & 1;  // Same as (count%2 == 1) 
}

bool intersectRayPlane(float3 rayOrigin, float3 rayDirection, float3 posOnPlane, float3 planeNormal, inout float3 intersectionPoint)
{
    float RdotN = dot(rayDirection, planeNormal);

    //parallel to plane or pointing away from plane?
    if (RdotN < 1e-5)
        return false;

    float s = dot(planeNormal, (posOnPlane - rayOrigin)) / RdotN;

    intersectionPoint = rayOrigin + s * rayDirection;

    return true;
}


bool isInAreaLight(in float3 objPosW, in float3 camPosW, out float3 isectPosW) 
{
    float3 V = objPosW - camPosW;
    float3 transV = mul(transMatIT, float4(V, 0)).xyz;
    float3 camPosL = mul(transMatIT, float4(camPosW, 1)).xyz;
    float3 objPosL = mul(transMatIT, float4(objPosW, 1)).xyz;
    float3 lightDir = float3(0, 0, 1);
    float3 intersectionPoint = float3(0, 0, 0);

    if (!intersectRayPlane(camPosL, transV, polygon[0].xyz, lightDir, intersectionPoint) && !intersectRayPlane(camPosL, transV, polygon[0].xyz, -lightDir, intersectionPoint)) return false;

    if (!isInside(intersectionPoint.xy)) return false;

    // check if polygon is behind scene geometry
    if (length(intersectionPoint - camPosL) > length(objPosL - camPosL)) return false;

    isectPosW = mul(transMat, float4(intersectionPoint, 1)).xyz;
    return true;
}


PsOut main(VertexOut vOut)
{
    ShadingData sd = prepareShadingData(vOut, gMaterial, gCamera.posW);
    float3 isectW;
    float lightFlag = 0;
    if (isInAreaLight(sd.posW, gCamera.posW, isectW))
    {
        lightFlag = 1;
        sd.posW = float3(isectW);
        sd.opacity = 1;
    }

    PsOut psOut;
    psOut.fragColor0 = float4(sd.posW, lightFlag);
    psOut.fragColor1 = float4(sd.N, sd.linearRoughness);
    psOut.fragColor2 = float4(sd.diffuse, sd.opacity);
    psOut.fragColor3 = float4(sd.specular, sd.roughness);

    return psOut;
}
