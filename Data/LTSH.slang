#ifndef _FALCOR_LTSH_SLANG_
#define _FALCOR_LTSH_SLANG_

// code taken from https://cseweb.ucsd.edu/~viscomp/projects/ash/, some refactoring was done to make glsl code base compile as hlsl/slang

__import ShaderCommon;
__import Lights;

static float PI = 3.14159265f;
static float INV_PI = 0.31830988618f;

SamplerState gSampler;
Texture2D<float4> gMinv;
Texture2D<float4> gLtshCoeff;

void getLtshCoeffs(float cosTheta, float roughness, out float[25] coeffs) {
    int l_idx = round(acos(cosTheta) * 63.f / 1.57079);
    int a_idx = round(sqrt(roughness) * 63.f);
    int3 coords = int3(l_idx, a_idx, 0);

    float4 texFetch;

    for (int i = 0; i < 6; i++) {
        texFetch = gLtshCoeff.Load(coords);
        coeffs[i * 4 + 0] = texFetch.r;
        coeffs[i * 4 + 1] = texFetch.g;
        coeffs[i * 4 + 2] = texFetch.b;
        coeffs[i * 4 + 3] = texFetch.a;
        coords.x += 64;
    }
    coeffs[24] = gLtshCoeff.Load(coords).r;
}

void Legendre(float x, out float[4] P) {    
    float X[4];
    X[1] = x;
    for (int j = 2; j < 4; j++) {
        X[j] = X[j-1] * X[1];
    }
    
    P[0] = 1;
    P[1] = x;
    P[2] = (0.5 * (3 * X[2] -1));
    P[3] = (0.5 * (5 * X[3] - 3*X[1]));
}

void boundary(float a, float b, float x, int maxN, out float[5] B_n) {
    
    float z = a*cos(x) + b*sin(x);
    float tmp1 = a*sin(x) - b*cos(x);
    float tmp2 = a*a+b*b-1;
    
    float P[4]; 
    Legendre(z, P);
    float Pa[4];
    Legendre(a, Pa);
    
    B_n[0] = x;
    B_n[1] = tmp1 + b;
    
	float D_next = 3 * B_n[1];
	float D_prev = x;
    
    for (int i = 2; i < maxN; i++) {
        float sf = 1.0/i;

        float C_n = (tmp1 * P[i-1]) + (tmp2 * D_prev) + ((i-1) * B_n[i-2]) + (b * Pa[i-1]);
        C_n *= sf;

		B_n[i] = (2*i-1) * C_n - (i - 1) * B_n[i - 2];
		B_n[i] *= sf;
		
		float temp = D_next;
		D_next = (2 * i + 1) * B_n[i] + D_prev;
		D_prev = temp;
    }
}


void evalLight(float3 dir, float3 verts[5], float3 gam[5], float3 gamP[5],
                    int maxN, int numVerts, out float[5] surf) {
    
    float total[5];

	float bound[5];
    boundary(dot(dir, verts[0]), dot(dir, gamP[0]), acos(dot(verts[0], verts[1])), maxN, bound);
	for (int n = 0; n < maxN; n++) {
		total[n] = bound[n] * dot(dir, gam[0]);
	}

    // i = 1
    boundary(dot(dir, verts[1]), dot(dir, gamP[1]), acos(dot(verts[1], verts[2])), maxN, bound);
    for (int n = 0; n < maxN; n++) {
        total[n] += bound[n] * dot(dir, gam[1]);
    }

    // i = 2
    boundary(dot(dir, verts[2]), dot(dir, gamP[2]), acos(dot(verts[2], verts[3 % numVerts])), maxN, bound);
    for (int n = 0; n < maxN; n++) {
        total[n] += bound[n] * dot(dir, gam[2]);
    }

    // i = 3
    if (numVerts >= 4) {
        boundary(dot(dir, verts[3]), dot(dir, gamP[3]), acos(dot(verts[3], verts[4 % numVerts])), maxN, bound);
        for (int n = 0; n < maxN; n++) {
            total[n] += bound[n] * dot(dir, gam[3]);
        }
    }

    if (numVerts >= 5) {
        boundary(dot(dir, verts[4]), dot(dir, gamP[4]), acos(dot(verts[4], verts[5 % numVerts])), maxN, bound);
        for (int n = 0; n < maxN; n++) {
            total[n] += bound[n] * dot(dir, gam[4]);
        }
    }

    surf[0] = 0;
    surf[1] = 0.5 * total[0];
    surf[2] = 0.5 * total[1];
    surf[3] = dot(float2(0.416667, 0.166667), float2(total[2], surf[1]));
    surf[4] = dot(float2(0.35, 0.3), float2(total[3], surf[2]));
}

float solid_angle(float3 verts[5], int numVerts) {
    float sa = 0;
    float3 tmp1 = cross(verts[0], verts[numVerts-1]);
    float3 tmp2 = cross(verts[0], verts[1]);
    sa += acos(dot(tmp1, tmp2) / (length(tmp1) * length(tmp2)));
    
    // Polygon will be at least a triangle
    // i = 1
    tmp1 = cross(verts[1], verts[0]);
    tmp2 = cross(verts[1], verts[2]);
    sa += acos(dot(tmp1, tmp2) / (length(tmp1) * length(tmp2)));

    // i = 2
    tmp1 = cross(verts[2], verts[1]);
    tmp2 = cross(verts[2], verts[3 % numVerts]);
    sa += acos(dot(tmp1, tmp2) / (length(tmp1) * length(tmp2)));

    if (numVerts >= 4) {
        tmp1 = cross(verts[3], verts[2]);
        tmp2 = cross(verts[3], verts[4 % numVerts]);
        sa += acos(dot(tmp1, tmp2) / (length(tmp1) * length(tmp2)));
    }
    if (numVerts >= 5) {
        tmp1 = cross(verts[4], verts[3]);
        tmp2 = cross(verts[4], verts[0]);   // for now let max vertices be 5
        sa += acos(dot(tmp1, tmp2) / (length(tmp1) * length(tmp2)));
    }

    sa -= (numVerts - 2) *PI;
    return sa;
}

void polygonSH(const in float3 L[5], int numVerts, out float[25] Lcoeff) {
    
    float3 G[5];
    G[0] = normalize(cross(L[0], L[1]));
    G[1] = normalize(cross(L[1], L[2]));
    G[2] = normalize(cross(L[2], L[3 % numVerts]));
    
    float3 Gp[5];
    Gp[0] = cross(G[0], L[0]);
    Gp[1] = cross(G[1], L[1]);
    Gp[2] = cross(G[2], L[2]);

    if (numVerts >= 4) {
        G[3] = normalize(cross(L[3], L[4 % numVerts]));
        Gp[3] = cross(G[3], L[3]);
    }
    if (numVerts >= 5) {
        G[4] = normalize(cross(L[4], L[5 % numVerts]));
        Gp[4] = cross(G[4], L[4]);
    }

    
    float SA = solid_angle(L, numVerts);
    int max_order = 4;
    
    for (int i = 0; i < 25; i++) {
        Lcoeff[i] = 0;
    }

    // Optimal lobe weights for bands 0 and 1
    Lcoeff[0] = 0.282095 * SA;

    float w20[5];
    evalLight((float3(0.866025, -0.500001, -0.000004)), L, G, Gp, max_order, numVerts, w20);
    float w21[5];
    evalLight((float3(-0.759553, 0.438522, -0.480394)), L, G, Gp, max_order, numVerts, w21);
    float w22[5];
    evalLight((float3(-0.000002, 0.638694, 0.769461)), L, G, Gp, max_order, numVerts, w22);
    float w23[5];
    evalLight((float3(-0.000004, -1.000000, -0.000004)), L, G, Gp, max_order, numVerts, w23);
    float w24[5];
    evalLight((float3(-0.000007, 0.000003, -1.000000)), L, G, Gp, max_order, numVerts, w24);
    float w25[5];
    evalLight((float3(-0.000002, -0.638694, 0.769461)), L, G, Gp, max_order, numVerts, w25);
    float w26[5];
    evalLight((float3(-0.974097, 0.000007, -0.226131)), L, G, Gp, max_order, numVerts, w26);
    float w27[5];
    evalLight((float3(-0.000003, 0.907079, -0.420960)), L, G, Gp, max_order, numVerts, w27);
    float w28[5];
    evalLight((float3(-0.960778, 0.000007, -0.277320)), L, G, Gp, max_order, numVerts, w28);

	Lcoeff[1] = dot(float3(2.1995339, 2.50785367, 1.56572711), float3(w20[1], w21[1], w22[1]));
	Lcoeff[2] = dot(float2(-1.82572523, -2.08165037), float2(w20[1], w21[1]));
	Lcoeff[3] = dot(float3(2.42459869, 1.44790525, 0.90397552), float3(w20[1], w21[1], w22[1]));

	Lcoeff[4] = dot(float3(-1.33331385, -0.66666684, -0.99999606), float3(w20[2], w23[2], w24[2]));
	Lcoeff[5] = dot(float3(1.1747938, -0.47923799, -0.69556433), float3(w22[2], w23[2], w24[2]));
	Lcoeff[6] = w24[2];
	Lcoeff[7] = dot(float3(-1.21710396, 1.58226094, 0.67825711), float3(w20[2], w21[2], w22[2]));
	Lcoeff[7] += dot(float2(-0.27666329, -0.76671491), float2(w23[2], w24[2]));
	Lcoeff[8] = dot(float2(-1.15470843, -0.57735948), float2(w23[2], w24[2]));
    
    Lcoeff[9] += dot(float3(-0.418128476395, 1.04704832111, 0.418135743058), float3(w22[3], w23[3], w25[3]));
    Lcoeff[10] += dot(float3(-0.217803921828, 1.61365275071, -0.0430709310435), float3(w20[3], w21[3], w22[3]));
    Lcoeff[10] += dot(float3(-1.08141635635, 0.730013109257, -0.906789272616), float3(w23[3], w24[3], w25[3]));
    Lcoeff[11] += dot(float3(0.539792926181, 0.281276817357, -0.53979650602), float3(w22[3], w23[3], w25[3]));
    Lcoeff[12] += -1.00000000026 * w24[3];
    Lcoeff[13] += dot(float4(-1.88563738164, 0.934959388519, -1.39846078802, -0.934977410564), float4(w20[3], w22[3], w23[3], w25[3]));
    Lcoeff[14] += dot(float3(-0.822588107798, 0.0250955547337, -0.822583092847), float3(w22[3], w24[3], w25[3]));
    Lcoeff[15] += dot(float3(-1.14577301943, 1.03584677217, -0.849735800355), float3(w20[3], w22[3], w23[3]));
    Lcoeff[15] += dot(float3(-0.438905584229, -0.100364975081, -1.36852983602), float3(w24[3], w25[3], w26[3]));

    Lcoeff[16] += dot(float3(-0.694140591095, -1.46594132085, -3.76291455607), float3(w20[4], w21[4], w22[4]));
    Lcoeff[16] += dot(float3(-4.19771773174, -4.41452625915, -5.21937739623), float3(w23[4], w24[4], w25[4]));
    Lcoeff[16] += dot(float3(30.1096083902, -0.582891410482, -25.58700736), float3(w26[4], w27[4], w28[4]));
    Lcoeff[17] += dot(float4(-0.776237001754, -0.497694700099, 0.155804529921, 0.255292423057), float4(w22[4], w23[4], w24[4], w25[4]));
    Lcoeff[17] += dot(float3(-0.00123151211175, 0.86352262597, 0.00106337156796), float3(w26[4], w27[4], w28[4]));
    Lcoeff[18] += dot(float3(1.14732747049, -1.93927453351, -4.97819284362), float3(w20[4], w21[4], w22[4]));
    Lcoeff[18] += dot(float3(-4.52057526927, -7.00211058681, -6.90497275343), float3(w23[4], w24[4], w25[4]));
    Lcoeff[18] += dot(float3(39.8336896922, -0.771083185249, -33.8504871326), float3(w26[4], w27[4], w28[4]));
    Lcoeff[19] += dot(float3(0.392392485498, -0.469375435363, 0.146862690526), float3(w22[4], w23[4], w24[4]));
    Lcoeff[19] += dot(float2(-0.883760925422, 0.81431736181), float2(w25[4], w27[4]));
    Lcoeff[20] += dot(float3(1.00015572278, -0.00110374505123, 0.000937958411459), float3(w24[4], w26[4], w28[4]));
    Lcoeff[21] += dot(float3(7.51111593422, 6.56318513992, 7.31626822687), float3(w22[4], w23[4], w24[4]));
    Lcoeff[21] += dot(float3(7.51109857163, -51.4260730066, 43.7016908482), float3(w25[4], w26[4], w28[4]));
    Lcoeff[22] += dot(float4(-0.61727564343, 0.205352092062, -0.461764665742, -0.617286413191), float4(w22[4], w23[4], w24[4], w25[4]));
    Lcoeff[23] += dot(float3(6.71336600734, 5.24419547627, 7.13550000457), float3(w22[4], w23[4], w24[4]));
    Lcoeff[23] += dot(float3(6.71337558899, -51.8339912003, 45.9921960339), float3(w25[4], w26[4], w28[4]));
    Lcoeff[24] += dot(float3(0.466450172383, 1.19684418958, -0.158210638771), float3(w22[4], w23[4], w24[4]));
    Lcoeff[24] += dot(float2(0.466416144347, 0.000906975300098), float2(w25[4], w26[4]));
    
}

float get_transfer_color(float Lc[25], int2 light_alpha_idx) {
    // Add envmap coefficient colors
    int3 idx = int3(light_alpha_idx, 0);
        
    float col_0 = gLtshCoeff.Load(idx).x * Lc[0];
    float col_1 = 0.4886025 * dot(gLtshCoeff.Load(idx).yzw, float4(Lc[0], Lc[1], Lc[2], Lc[3]).yzw);

    idx.x += 64;
    float col_2 = dot(gLtshCoeff.Load(idx), float4(Lc[4], Lc[5], Lc[6], Lc[7]));
    idx.x += 64;
    float4 temp = gLtshCoeff.Load(idx);
    col_2 += temp.x * Lc[8];
    col_2 *= 0.6307831;

    float col_3 = dot(temp.yzw, float3(Lc[9], Lc[10], Lc[11]));
    idx.x += 64;
    col_3 += dot(gLtshCoeff.Load(idx), float4(Lc[12], Lc[13], Lc[14], Lc[15]));
    col_3 *= 0.746353;
    
    idx.x += 64;
    float col_4 = dot(gLtshCoeff.Load(idx), float4(Lc[16], Lc[17], Lc[18], Lc[19]));
    idx.x += 64;
    col_4 += dot(gLtshCoeff.Load(idx), float4(Lc[20], Lc[21], Lc[22], Lc[23]));
    
    idx.x += 64;
    float4 temp2 = gLtshCoeff.Load(idx);
    col_4 += temp2.x * Lc[24];
    col_4 *= 0.8462844; 
    
    float result = col_0 + col_1 + col_2 + col_3 + col_4;
    return max(0, result);

}

float evaluateSH(float x, float y, float z, float[25] coefficients) {
    float legendre0_0 = 1.0;
    float legendre1_0 = 1.00000000000000000e+00 * z * legendre0_0;
    float legendre1_1 = -1.00000000000000000e+00 * legendre0_0;
    float legendre2_0 = 1.50000000000000000e+00 * z * legendre1_0 - 
    5.00000000000000000e-01 * legendre0_0;
    float legendre2_1 = 3.00000000000000000e+00 * z * legendre1_1;
    float legendre2_2 = -3.00000000000000000e+00 * legendre1_1;
    float legendre3_0 = 1.66666666666666674e+00 * z * legendre2_0 - 
    6.66666666666666630e-01 * legendre1_0;
    float legendre3_1 = 2.50000000000000000e+00 * z * legendre2_1 - 
    1.50000000000000000e+00 * legendre1_1;
    float legendre3_2 = 5.00000000000000000e+00 * z * legendre2_2;
    float legendre3_3 = -5.00000000000000000e+00 * legendre2_2;
    float legendre4_0 = 1.75000000000000000e+00 * z * legendre3_0 - 
    7.50000000000000000e-01 * legendre2_0;
    float legendre4_1 = 2.33333333333333348e+00 * z * legendre3_1 - 
    1.33333333333333326e+00 * legendre2_1;
    float legendre4_2 = 3.50000000000000000e+00 * z * legendre3_2 - 
    2.50000000000000000e+00 * legendre2_2;
    float legendre4_3 = 7.00000000000000000e+00 * z * legendre3_3;
    float legendre4_4 = -7.00000000000000000e+00 * legendre3_3;
    float cosine0 = 1.0;
    float sine0 = 0.0;
    float cosine1 = x * cosine0 - y * sine0;
    float sine1 = x * sine0 + y * cosine0;
    float cosine2 = x * cosine1 - y * sine1;
    float sine2 = x * sine1 + y * cosine1;
    float cosine3 = x * cosine2 - y * sine2;
    float sine3 = x * sine2 + y * cosine2;
    float cosine4 = x * cosine3 - y * sine3;
    float sine4 = x * sine3 + y * cosine3;

    float pSH[25];

    pSH[0] = 2.82094791773878140e-01 * cosine0 * legendre0_0;
    pSH[1] = 4.88602511902919923e-01 * sine1 * legendre1_1;
    pSH[2] = 4.88602511902919923e-01 * cosine0 * legendre1_0;
    pSH[3] = 4.88602511902919923e-01 * cosine1 * legendre1_1;
    pSH[4] = 1.82091405098679854e-01 * sine2 * legendre2_2;
    pSH[5] = 3.64182810197359708e-01 * sine1 * legendre2_1;
    pSH[6] = 6.30783130505040091e-01 * cosine0 * legendre2_0;
    pSH[7] = 3.64182810197359708e-01 * cosine1 * legendre2_1;
    pSH[8] = 1.82091405098679854e-01 * cosine2 * legendre2_2;
    pSH[9] = 3.93362393284428999e-02 * sine3 * legendre3_3;
    pSH[10] = 9.63537147546851408e-02 * sine2 * legendre3_2;
    pSH[11] = 3.04697199642977146e-01 * sine1 * legendre3_1;
    pSH[12] = 7.46352665180230801e-01 * cosine0 * legendre3_0;
    pSH[13] = 3.04697199642977146e-01 * cosine1 * legendre3_1;
    pSH[14] = 9.63537147546851408e-02 * cosine2 * legendre3_2;
    pSH[15] = 3.93362393284428999e-02 * cosine3 * legendre3_3;
    pSH[16] = 5.96034033761120175e-03 * sine4 * legendre4_4;
    pSH[17] = 1.68583882836183876e-02 * sine3 * legendre4_3;
    pSH[18] = 6.30783130505040007e-02 * sine2 * legendre4_2;
    pSH[19] = 2.67618617422915650e-01 * sine1 * legendre4_1;
    pSH[20] = 8.46284375321634474e-01 * cosine0 * legendre4_0;
    pSH[21] = 2.67618617422915650e-01 * cosine1 * legendre4_1;
    pSH[22] = 6.30783130505040007e-02 * cosine2 * legendre4_2;
    pSH[23] = 1.68583882836183876e-02 * cosine3 * legendre4_3;
    pSH[24] = 5.96034033761120175e-03 * cosine4 * legendre4_4;

    float sum = 0;

    for (int i = 0; i < 25; i++) {
        sum += pSH[i] * coefficients[i];
    }
    return sum;
}

float3 evalLtshBrdf(ShadingData sd, LightSample ls, float3x3 MInv, float[25] coefficients) {
    float3 LInv = mul(MInv, ls.L);
    float D = abs(determinant(MInv));
    float L_ = length(LInv);
    float jacob = D / (L_ * L_ * L_);

    LInv = normalize(LInv);

    float val = evaluateSH(LInv.x, LInv.y, LInv.z, coefficients) * jacob;
    return float3(val, val, val);
}

#endif	// _FALCOR_LTSH_SLANG_
