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

    switch (mData.type)
    {

    case LightAreaRect:
    {
        float rx = glm::length(mData.transMat * vec4(1.0f, 0.0f, 0.0f, 0.0f));
        float ry = glm::length(mData.transMat * vec4(0.0f, 1.0f, 0.0f, 0.0f));
        mData.surfaceArea = 4.0f * rx * ry;
    }
    break;

    case LightAreaSphere:
    {
        float rx = glm::length(mData.transMat * vec4(1.0f, 0.0f, 0.0f, 0.0f));
        float ry = glm::length(mData.transMat * vec4(0.0f, 1.0f, 0.0f, 0.0f));
        float rz = glm::length(mData.transMat * vec4(0.0f, 0.0f, 1.0f, 0.0f));

        mData.surfaceArea = 4.0f * (float)M_PI * pow(pow(rx * ry, 1.6f) + pow(ry * rz, 1.6f) + pow(rx * rz, 1.6f) / 3.0f, 1.0f / 1.6f);
    }
    break;

    case LightAreaDisc:
    {
        float rx = glm::length(mData.transMat * vec4(1.0f, 0.0f, 0.0f, 0.0f));
        float ry = glm::length(mData.transMat * vec4(0.0f, 1.0f, 0.0f, 0.0f));

        mData.surfaceArea = (float)M_PI * rx * ry;
    }
    break;

    default:
        break;
    }
}

void SimpleAreaLight::move(const glm::vec3 & position, const glm::vec3 & target, const glm::vec3 & up)
{
    mTransformMatrix = glm::inverse(glm::lookAt(position, 2.0f * position - target, up));   // Some math gymnastics to compensate for lookat returning the inverse matrix (suitable for camera), while we want to point the light source
    update();
}