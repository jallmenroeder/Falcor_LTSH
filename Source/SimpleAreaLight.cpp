#include "SimpleAreaLight.h"
#include "PolygonUtil.h"


// Code for simple area lights.
SimpleAreaLight::SharedPtr SimpleAreaLight::create()
{
    SimpleAreaLight* pLight = new SimpleAreaLight;
    return SharedPtr(pLight);
}

SimpleAreaLight::SimpleAreaLight()
{
    mData.type = LightArea;
    mVertices2d = std::vector<glm::vec2>({
        glm::vec2(-1.f, 1.f),
        glm::vec2(-1.f, -1.f),
        glm::vec2(1.f, -1.f),
        glm::vec2(1.f, 1.f)
    });
    mNumVertices = mVertices2d.size();

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
    mData.transMat = mTransformMatrix * glm::scale(glm::mat4(), glm::vec3(mScaling, 1.f));
    mData.transMatIT = glm::inverse(glm::transpose(mData.transMat));
    mData.dirW = glm::normalize(glm::vec3(mData.transMat * glm::vec4(0.f, 0.f, -1.f, 0.f)));

    mNumVertices = mVertices2d.size();

    // calculate surface area (ref: https://web.archive.org/web/20100405070507/http://valis.cs.uiuc.edu/~sariel/research/CG/compgeom/msg00831.html)
    // note that vertices must be counter clockwise, else the result will be negative
    mData.surfaceArea = 0.f;
    for (int i = 0; i < mNumVertices; ++i)
    {
        int j = (i + 1) % mNumVertices;
        mData.surfaceArea += mVertices2d[i].x * mVertices2d[j].y * mScaling.x * mScaling.y;
        mData.surfaceArea -= mVertices2d[i].y * mVertices2d[j].x * mScaling.x * mScaling.y;
    }
    mData.surfaceArea = mData.surfaceArea / 2.f;

    // calculate the transformed vertices in worldspace, also find min and max
    mMin = glm::vec2(std::numeric_limits<float>::max(), std::numeric_limits<float>::max());
    mMax = glm::vec2(std::numeric_limits<float>::min(), std::numeric_limits<float>::min());
    std::vector<glm::vec3> vertices_3d = std::vector<glm::vec3>();
    mTransformedVertices3d.clear();
    mScaledVertices2d.clear();
    for (auto vert_2d: mVertices2d)
    {
        vertices_3d.emplace_back(glm::vec3(vert_2d.x, vert_2d.y, 0.f));
        mScaledVertices2d.emplace_back(vert_2d * mScaling);
        mMin = glm::min(vert_2d * mScaling, mMin);
        mMax = glm::max(vert_2d * mScaling, mMax);
    }

    for (auto vert_3d : vertices_3d)
    {
        mTransformedVertices3d.emplace_back(glm::vec3(mData.transMat * glm::vec4(vert_3d, 1.f)));
    }

    // create new samples
    this->createSamples(NUM_SAMPLES);
}

void SimpleAreaLight::move(const glm::vec3 & position, const glm::vec3 & target, const glm::vec3 & up)
{
    mTransformMatrix = glm::inverse(glm::lookAt(position, target, up));   // Some math gymnastics to compensate for lookat returning the inverse matrix (suitable for camera), while we want to point the light source
    update();
}

// simple rejection sampling
void SimpleAreaLight::createSamples(int n)
{
    int sampleCount = 0;
    glm::vec2 extent = mMax - mMin;

    while (sampleCount < n)
    {
        // get two random values in [0, 1]
        glm::vec2 sample = glm::vec2((float)std::rand() / RAND_MAX, (float)std::rand() / RAND_MAX);
        // move sample to polygon space
        sample = sample * extent + mMin;
        if (PolygonUtil::isInside(mScaledVertices2d, (int)mNumVertices, sample))
        {
            mSamples[sampleCount] = float4(sample.x, sample.y, 0.f, 1.f);
            sampleCount++;
        }
    }
}

void SimpleAreaLight::setSamplesIntoProgramVars(ProgramVars* pVars, ConstantBuffer* pCb, const std::string& varName)
{
    size_t offset = pCb->getVariableOffset(varName);

    pCb->setBlob(&mSamples, offset, sizeof(mSamples));
}
