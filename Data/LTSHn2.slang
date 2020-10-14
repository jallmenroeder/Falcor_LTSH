#ifndef _FALCOR_LTSH_N2_SLANG_
#define _FALCOR_LTSH_N2_SLANG_

// The following code is mostly taken from https://cseweb.ucsd.edu/~viscomp/projects/ash/, some refactoring was done to make glsl code base compile as hlsl/slang

__import LTSH;

Texture2D<float4> gLtshMinvN2;
Texture2D<float4> gLtshCoeffN2;

float3x3 getLtshMatrixN2(in int2 uv)
{
    int3 indices = int3(uv, 0);
    float4 matVec = gLtshMinvN2.Load(indices);
    float3x3 mat = float3x3(
        1, 0, matVec.z,
        0, matVec.y, 0,
        matVec.x, 0, matVec.w
    );

    return mat;
}

void getLtshCoeffsN2(in int2 uv, out float[9] coeffs) {
    float4 texFetch;
    int3 indices = int3(uv, 0);

    // all the odd coefficients need to be negated due to a different convention in the Wang/Ramamoorthi code
    for (int i = 0; i < 2; i++) {
        texFetch = gLtshCoeffN2.Load(indices);
        coeffs[i * 4 + 0] = texFetch.r;
        coeffs[i * 4 + 1] = -texFetch.g;
        coeffs[i * 4 + 2] = texFetch.b;
        coeffs[i * 4 + 3] = -texFetch.a;
        indices.x += 64;
    }
    coeffs[8] = gLtshCoeffN2.Load(indices).r;
}

void boundaryN2(float a, float b, float x, int maxN, inout float B_n[3]) {
    float z = a*cos(x) + b*sin(x);
    float tmp1 = a*sin(x) - b*cos(x);
    float tmp2 = a*a+b*b-1.0;

    B_n[0] = x;
    B_n[1] = tmp1 + b;

    float D_prev = x;

    float C_n = (tmp1 * z) + (tmp2 * D_prev) + (B_n[0]) + (b * a);
    C_n *= .5f;

    B_n[2] = (3.0 * C_n - B_n[0]) * .5f;
}

void evalLightN2(float3 dir, float3 verts[5], float3 gam[5], float3 gamP[5], int maxN, int numVerts, inout float[3] surf) {
    
    float total[3];

	float bound[3];
    boundaryN2(dot(dir, verts[0]), dot(dir, gamP[0]),
		acos(dot(verts[0], verts[1])), maxN, bound);
	for (int n = 0; n < maxN; n++) {
		total[n] = bound[n] * dot(dir, gam[0]);
	}

    // i = 1
    boundaryN2(dot(dir, verts[1]), dot(dir, gamP[1]), acos(dot(verts[1], verts[2])), maxN, bound);
    for (int n = 0; n < maxN; n++) {
        total[n] += bound[n] * dot(dir, gam[1]);
    }

    // i = 2
    boundaryN2(dot(dir, verts[2]), dot(dir, gamP[2]), acos(dot(verts[2], verts[3 % numVerts])), maxN, bound);
    for (int n = 0; n < maxN; n++) {
        total[n] += bound[n] * dot(dir, gam[2]);
    }

    // i = 3
    if (numVerts >= 4) {
        boundaryN2(dot(dir, verts[3]), dot(dir, gamP[3]), acos(dot(verts[3], verts[4 % numVerts])), maxN, bound);
        for (int n = 0; n < maxN; n++) {
            total[n] += bound[n] * dot(dir, gam[3]);
        }
    }

    if (numVerts >= 5) {
        boundaryN2(dot(dir, verts[4]), dot(dir, gamP[4]), acos(dot(verts[4], verts[5 % numVerts])), maxN, bound);
        for (int n = 0; n < maxN; n++) {
            total[n] += bound[n] * dot(dir, gam[4]);
        }
    }

    surf[1] = 0.5 * total[0];
    surf[2] = 0.5 * total[1];

    for (int i = 1; i < 3; i++) {
        surf[i] *= sqrt((2.0 * float(i) + 1.0) / (4.0 * PI));
    }
}

void polygonSHN2(float3 L[5], int numVerts, inout float Lcoeff[9]) {
    float3 G[5];
    G[0] = normalize(cross(L[0], L[1]));
    G[1] = normalize(cross(L[1], L[2]));
    G[2] = normalize(cross(L[2], L[3]));
    G[3] = normalize(cross(L[3], L[4]));
    G[4] = normalize(cross(L[4], L[0]));

    float3 Gp[5];
    Gp[0] = cross(G[0], L[0]);
    Gp[1] = cross(G[1], L[1]);
    Gp[2] = cross(G[2], L[2]);
    Gp[3] = cross(G[3], L[3]);
    Gp[4] = cross(G[4], L[4]);

    float SA = solid_angle(L, numVerts);

    Lcoeff[0] = 0.282095 * SA;

    float w20[3];
    evalLightN2((float3(0.866025, -0.500001, -0.000004)), L, G, Gp, 2, numVerts, w20);
    float w21[3];
    evalLightN2((float3(-0.759553, 0.438522, -0.480394)), L, G, Gp, 2, numVerts, w21);
    float w22[3];
    evalLightN2((float3(-0.000002, 0.638694, 0.769461)), L, G, Gp, 2, numVerts, w22);
    float w23[3];
    evalLightN2((float3(-0.000004, -1.000000, -0.000004)), L, G, Gp, 2, numVerts, w23);
    float w24[3];
    evalLightN2((float3(-0.000007, 0.000003, -1.000000)), L, G, Gp, 2, numVerts, w24);


    Lcoeff[1] = dot(float3(2.1995339, 2.50785367, 1.56572711), float3(w20[1], w21[1], w22[1]));
    Lcoeff[2] = dot(float2(-1.82572523, -2.08165037), float2(w20[1], w21[1]));
    Lcoeff[3] = dot(float3(2.42459869, 1.44790525, 0.90397552), float3(w20[1], w21[1], w22[1]));

    Lcoeff[4] = dot(float3(-1.33331385, -0.66666684, -0.99999606), float3(w20[2], w23[2], w24[2]));
    Lcoeff[5] = dot(float3(1.1747938, -0.47923799, -0.69556433), float3(w22[2], w23[2], w24[2]));
    Lcoeff[6] = w24[2];
    Lcoeff[7] = dot(float3(-1.21710396, 1.58226094, 0.67825711), float3(w20[2], w21[2], w22[2]));
    Lcoeff[7] += dot(float2(-0.27666329, -0.76671491), float2(w23[2], w24[2]));
    Lcoeff[8] = dot(float2(-1.15470843, -0.57735948), float2(w23[2], w24[2]));
}

#endif	// _FALCOR_LTSH_N2_SLANG_
