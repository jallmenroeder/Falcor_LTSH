#ifndef _FALCOR_AREA_LIGHT_UTIL_SLANG_
#define _FALCOR_AREA_LIGHT_UTIL_SLANG_

__import Lights;
__import BRDF;
__import Shading;

/** Evaluate an area light source intensity/direction at a shading point
*/
ShadingResult evalMaterialAreaLight(ShadingData sd, AreaLightData light, float shadowFactor)
{
	ShadingResult sr = initShadingResult();
	LightSample ls = evalAreaLight(light, sd.posW);
	calcCommonLightProperties(sd, ls);

	// If the light doesn't hit the surface or we are viewing the surface from the back, return
	if (ls.NdotL <= 0) return sr;
	sd.NdotV = saturate(sd.NdotV);

	// Calculate the diffuse term
	sr.diffuseBrdf = saturate(evalDiffuseBrdf(sd, ls));
	sr.diffuse = ls.diffuse * sr.diffuseBrdf * ls.NdotL;
	sr.color.rgb = sr.diffuse;
	sr.color.a = sd.opacity;

	// Calculate the specular term
	sr.specularBrdf = saturate(evalSpecularBrdf(sd, ls));
	sr.specular = ls.specular * sr.specularBrdf * ls.NdotL;
	sr.color.rgb += sr.specular;

	// Apply the shadow factor
	sr.color.rgb *= shadowFactor;

	return sr;
};
#endif //_FALCOR_AREA_LIGHT_UTIL_SLANG_
