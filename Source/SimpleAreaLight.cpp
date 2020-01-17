#include "SimpleAreaLight.h"


// Code for simple area lights.
SimpleAreaLight::SharedPtr SimpleAreaLight::create()
{
    SimpleAreaLight* pLight = new SimpleAreaLight;
    return SharedPtr(pLight);
}

SimpleAreaLight::SimpleAreaLight()
{
    mData.type = LightArea;
    mData.tangent = float3(1, 0, 0);
    mData.bitangent = float3(0, 1, 0);
	mVertices2d = std::vector<glm::vec2>({
		glm::vec2(-1.f, 1.f),
		glm::vec2(-1.f, -1.f),
		glm::vec2(1.f, -1.f),
		glm::vec2(1.f, 1.f)
	});
	mNumVertices = mVertices2d.size();
	mData.surfaceArea = 4.0f;

    mScaling = vec3(1, 1, 1);
    update();
}

SimpleAreaLight::~SimpleAreaLight() = default;

float SimpleAreaLight::getPower() const
{
    return luminance(mData.intensity) * (float)M_PI * mData.surfaceArea;
}

void SimpleAreaLight::renderUI(Gui * pGui, const char* group)
{
    if (!group || pGui->beginGroup(group))
    {
        Light::renderUI(pGui);

        if (group)
        {
            pGui->endGroup();
        }
    }
}

void SimpleAreaLight::update()
{
    // Update matrix
    mData.transMat = mTransformMatrix * glm::scale(glm::mat4(), mScaling);
    mData.transMatIT = glm::inverse(glm::transpose(mData.transMat));

	mNumVertices = mVertices2d.size();

    // calculate surface area (ref: https://web.archive.org/web/20100405070507/http://valis.cs.uiuc.edu/~sariel/research/CG/compgeom/msg00831.html)
	// note that vertices must be counter clockwise, else the result will be negative
	mData.surfaceArea = 0.f;
	for (int i = 0; i < mNumVertices; ++i)
	{
		int j = (i + 1) % mNumVertices;
		mData.surfaceArea += mVertices2d[i].x * mVertices2d[j].y;
		mData.surfaceArea -= mVertices2d[i].y * mVertices2d[j].x;
	}
	mData.surfaceArea = mData.surfaceArea / 2.f;

	// calculate the transformed vertices in worldspace
	std::vector<glm::vec3> vertices_3d = std::vector<glm::vec3>();
	mTransformedVertices3d.clear();
	for (auto vert_2d: mVertices2d)
	{
		vertices_3d.emplace_back(glm::vec3(vert_2d.x, vert_2d.y, 0.f));
	}

	for (auto vert_3d : vertices_3d)
	{
		mTransformedVertices3d.emplace_back(glm::vec3(mData.transMat * glm::vec4(vert_3d, 1.f)));
	}
}

void SimpleAreaLight::move(const glm::vec3 & position, const glm::vec3 & target, const glm::vec3 & up)
{
    mTransformMatrix = glm::inverse(glm::lookAt(position, 2.0f * position - target, up));   // Some math gymnastics to compensate for lookat returning the inverse matrix (suitable for camera), while we want to point the light source
    update();
}