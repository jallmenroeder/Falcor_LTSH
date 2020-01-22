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

__import Shading;

struct PsOut
{
    float4 fragColor0 : SV_TARGET0;
    float4 fragColor1 : SV_TARGET1;
    float4 fragColor2 : SV_TARGET2;
    float4 fragColor3 : SV_TARGET3;
    float4 fragColor4 : SV_TARGET4;
};


PsOut main(VertexOut vOut)
{
    ShadingData sd = prepareShadingData(vOut, gMaterial, gCamera.posW);

    PsOut psOut;
    psOut.fragColor0 = float4(sd.posW, 1);
    psOut.fragColor1 = float4(sd.N, sd.linearRoughness);
    psOut.fragColor2 = float4(sd.diffuse, sd.opacity);
    psOut.fragColor3 = float4(sd.specular, sd.roughness);
    psOut.fragColor4 = float4(gCamera.posW, 1);

    return psOut;
}
