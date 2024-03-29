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
#include "SimpleDeferred.h"
#include "PolygonUtil.h"
#include "Numpy.hpp"

//const std::string SimpleDeferred::skDefaultModel = "Media/SunTemple/SunTemple.fbx";
//const std::string SimpleDeferred::skDefaultModel = "Media/sponza/sponza.dae";
//const std::string SimpleDeferred::skDefaultModel = "Media/plane.dae";
const std::string SimpleDeferred::skDefaultModel = "Media/Arcade/Arcade.fbx";

const int legendre_res = 10000;

// convert matrix data read from .npy file to a buffer which can written in the texture
void convertFloat32ToFloat16(const std::vector<float>& in, std::vector<glm::detail::hdata>& out)
{
    out.clear();
    for (auto val : in)
    {
        out.push_back(glm::detail::toFloat16(float(val)));
    }
}

void convertDoubleToFloat16(const std::vector<double>& in, std::vector<glm::detail::hdata>& out)
{
    out.clear();
    for (auto val : in)
    {
        out.push_back(glm::detail::toFloat16(float(val)));
    }
}

// convert ltsh coefficient data read from .npy file to a buffer which can written in the texture, differs from ltc becaus ltsh has more coefficients
void convertLtshCoeff(const std::vector<double>& in, std::vector<glm::detail::hdata>& out)
{
    // we only need 25 coefficients but to fit the RGBA texture we pad to 28, this gives 7 64x64 fields containing 4(RGBA) coefficients
    out = std::vector<glm::detail::hdata>(64 * 64 * 28);
    for (size_t i = 0; i < 64; i++)
    {
        for (size_t j = 0; j < 64; j++)
        {
            for (size_t k = 0; k < 28; k++)
            {
                // (k / 4) * 4 seems unnecessary but since it is integer division it gives us the right offset
                size_t offset = (k / 4) * 64 * 4;
                // add pad value
                if (k > 24)
                {
                    out[i * 64 * 28 + j * 4 + (k % 4) + offset] = glm::detail::toFloat16(0.f);
                    continue;
                }
                // order has to be rewritten to match texture format
                out[i * 64 * 28 + j * 4 + (k % 4) + offset] = glm::detail::toFloat16(float(in[j * 64 * 25 + i * 25 + k]));
            }
        }
    }
}

// convert ltsh coefficient data read from .npy file to a buffer which can written in the texture, differs from ltc becaus ltsh has more coefficients
void convertLtshCoeffN2(const std::vector<double>& in, std::vector<glm::detail::hdata>& out)
{
    // we only need 9 coefficients but to fit the RGBA texture we pad to 12, this gives 3 64x64 fields containing 4(RGBA) coefficients
    out = std::vector<glm::detail::hdata>(64 * 64 * 12);
    for (size_t i = 0; i < 64; i++)
    {
        for (size_t j = 0; j < 64; j++)
        {
            for (size_t k = 0; k < 12; k++)
            {
                // (k / 4) * 4 seems unnecessary but since it is integer division it gives us the right offset
                size_t offset = (k / 4) * 64 * 4;
                // add pad value
                if (k > 8)
                {
                    out[i * 64 * 12 + j * 4 + (k % 4) + offset] = glm::detail::toFloat16(0.f);
                    continue;
                }
                // order has to be rewritten to match texture format
                out[i * 64 * 12 + j * 4 + (k % 4) + offset] = glm::detail::toFloat16(float(in[j * 64 * 9 + i * 9 + k]));
            }
        }
    }
}

SimpleDeferred::~SimpleDeferred()
{
}

CameraController& SimpleDeferred::getActiveCameraController()
{
    switch(mCameraType)
    {
    case SimpleDeferred::ModelViewCamera:
        return mModelViewCameraController;
    case SimpleDeferred::FirstPersonCamera:
        return mFirstPersonCameraController;
    default:
        should_not_get_here();
        return mFirstPersonCameraController;
    }
}

void SimpleDeferred::loadModelFromFile(const std::string& filename, Fbo* pTargetFbo)
{
    Model::LoadFlags flags = Model::LoadFlags::None;
    if (mGenerateTangentSpace == false)
    {
        flags |= Model::LoadFlags::DontGenerateTangentSpace;
    }
    auto fboFormat = pTargetFbo->getColorTexture(0)->getFormat();
    flags |= isSrgbFormat(fboFormat) ? Model::LoadFlags::None : Model::LoadFlags::AssumeLinearSpaceTextures;

    mpModel = Model::createFromFile(filename.c_str(), flags);

    if(mpModel == nullptr)
    {
        msgBox("Could not load model");
        return;
    }
    resetCamera();

    float Radius = mpModel->getRadius();
    mpPointLight->setWorldPosition(glm::vec3(0, Radius*1.25f, 0));
}

void SimpleDeferred::loadModel(Fbo* pTargetFbo)
{
    std::string filename;
    if(openFileDialog(Model::kFileExtensionFilters, filename))
    {
        loadModelFromFile(filename, pTargetFbo);
    }
}

void SimpleDeferred::onGuiRender(SampleCallbacks* pSample, Gui* pGui)
{
    // Load model group
    if (pGui->addButton("Load Model"))
    {
        loadModel(pSample->getCurrentFbo().get());
    }

    if(pGui->beginGroup("Load Options"))
    {
        pGui->addCheckBox("Generate Tangent Space", mGenerateTangentSpace);
        pGui->endGroup();
    }

    Gui::DropdownList debugModeList;
    debugModeList.push_back({ 0, "Disabled" });
    debugModeList.push_back({ 1, "Positions" });
    debugModeList.push_back({ 2, "Normals" });
    debugModeList.push_back({ 3, "Albedo" });
    debugModeList.push_back({ 4, "Illumination" });
    debugModeList.push_back({ 5, "Diffuse" });
    debugModeList.push_back({ 6, "Specular" });
    pGui->addDropdown("Debug mode", debugModeList, (uint32_t&)mDebugMode);

    Gui::DropdownList areaLightRenderModeList;
    areaLightRenderModeList.push_back({ 0, "Ground Truth" });
    areaLightRenderModeList.push_back({ 1, "LTC" });
    areaLightRenderModeList.push_back({ 2, "LTSH_N4" });
    areaLightRenderModeList.push_back({ 6, "LTSH_N2" });
    areaLightRenderModeList.push_back({ 3, "None" });
    areaLightRenderModeList.push_back({ 4, "GT with LTC BRDF" });
    areaLightRenderModeList.push_back({ 5, "GT with LTSH_N4 BRDF" });
    pGui->addDropdown("Area Light Render Mode", areaLightRenderModeList, (uint32_t&)mAreaLightRenderMode);

    Gui::DropdownList cullList;
    cullList.push_back({0, "No Culling"});
    cullList.push_back({1, "Backface Culling"});
    cullList.push_back({2, "Frontface Culling"});
    pGui->addDropdown("Cull Mode", cullList, (uint32_t&)mCullMode);

    if(pGui->beginGroup("Lights"))
    {
        pGui->addRgbColor("Ambient intensity", mAmbientIntensity);
        if(pGui->beginGroup("Directional Light"))
        {
            mpDirLight->renderUI(pGui);
            pGui->endGroup();
        }
        if (pGui->beginGroup("Point Light"))
        {
            mpPointLight->renderUI(pGui);
            pGui->endGroup();
        }
        if (pGui->beginGroup("Area Light"))
        {
            mpAreaLight->renderUI(pGui);
            pGui->endGroup();
        }
        pGui->endGroup();
    }

    Gui::DropdownList cameraList;
    cameraList.push_back({ FirstPersonCamera, "First-Person" });
    cameraList.push_back({ModelViewCamera, "Model-View"});
    pGui->addDropdown("Camera Type", cameraList, (uint32_t&)mCameraType);

    if (mpModel)
    {
        renderModelUiElements(pGui);
    }
}

void SimpleDeferred::renderModelUiElements(Gui* pGui)
{
    bool bAnim = mpModel->hasAnimations();
    static const char* animateStr = "Animate";
    static const char* activeAnimStr = "Active Animation";

    if(bAnim)
    {
        mActiveAnimationID = sBindPoseAnimationID;

        pGui->addCheckBox(animateStr, mAnimate);
        Gui::DropdownList list;
        list.resize(mpModel->getAnimationsCount() + 1);
        list[0].label = "Bind Pose";
        list[0].value = sBindPoseAnimationID;

        for(uint32_t i = 0; i < mpModel->getAnimationsCount(); i++)
        {
            list[i + 1].value = i;
            list[i + 1].label = mpModel->getAnimationName(i);
            if(list[i + 1].label.size() == 0)
            {
                list[i + 1].label = std::to_string(i);
            }
        }
        if (pGui->addDropdown(activeAnimStr, list, mActiveAnimationID))
        {
            mpModel->setActiveAnimation(mActiveAnimationID);
        }
    }
    if(pGui->beginGroup("Depth Range"))
    {
        const float minDepth = mpModel->getRadius() * 1 / 1000;
        pGui->addFloatVar("Near Plane", mNearZ, minDepth, mpModel->getRadius() * 15, minDepth * 5);
        pGui->addFloatVar("Far Plane", mFarZ, minDepth, mpModel->getRadius() * 15, minDepth * 5);
        pGui->endGroup();
    }
}

void SimpleDeferred::onLoad(SampleCallbacks* pSample, RenderContext* pRenderContext)
{
    mpCamera = Camera::create();

    mpDeferredPassProgram = GraphicsProgram::createFromFile("DeferredPass.ps.hlsl", "", "main");

    mpLightingPass = FullScreenPass::create("LightingPass.ps.hlsl");

    // create rasterizer state
    RasterizerState::Desc rsDesc;
    mpCullRastState[0] = RasterizerState::create(rsDesc);
    rsDesc.setCullMode(RasterizerState::CullMode::Back);
    mpCullRastState[1] = RasterizerState::create(rsDesc);
    rsDesc.setCullMode(RasterizerState::CullMode::Front);    mpCullRastState[2] = RasterizerState::create(rsDesc);

    // Depth test
    DepthStencilState::Desc dsDesc;
    dsDesc.setDepthTest(false);
    mpNoDepthDS = DepthStencilState::create(dsDesc);
    dsDesc.setDepthTest(true);
    mpDepthTestDS = DepthStencilState::create(dsDesc);

    // Blend state
    BlendState::Desc blendDesc;
    mpOpaqueBS = BlendState::create(blendDesc);

    mModelViewCameraController.attachCamera(mpCamera);
    mFirstPersonCameraController.attachCamera(mpCamera);

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Linear).setMaxAnisotropy(8);
    mpLinearSampler = Sampler::create(samplerDesc);

    mpPointLight = PointLight::create();
    mpPointLight->setIntensity(glm::vec3(0.f));
    mpDirLight = DirectionalLight::create();
    mpDirLight->setIntensity(glm::vec3(0));
    mpDirLight->setWorldDirection(glm::vec3(-0.5f, -0.2f, -1.0f));

    mpAreaLight = SimpleAreaLight::create();
    mpAreaLight->setScaling(glm::vec3(.25f, .25f, 1.f));
    glm::vec3 pos = glm::vec3(-.5f, .7f, -0.5f);
    glm::vec3 pivot = pos + glm::vec3(.2f, 0.f, .98f);
    glm::vec3 up = glm::vec3(0.f, 1.f, 0.f);
    mpAreaLight->move(pos, pivot, up);
    mpAreaLight->setIntensity(glm::vec3(150.f, 150.f, 150.f));

    mAreaLightRenderMode = AreaLightRenderMode::LTSH;
    mDebugMode = DebugMode::Specular;

    mpDeferredVars = GraphicsVars::create(mpDeferredPassProgram->getReflector());
    mpLightingVars = GraphicsVars::create(mpLightingPass->getProgram()->getReflector());

    std::vector<double> d_temp = std::vector<double>();
    std::vector<float> f_temp = std::vector<float>();
    std::vector<glm::detail::hdata> data = std::vector<glm::detail::hdata>();


    // Load LTC matrices
    aoba::LoadArrayFromNumpy("Data/Params/inv_cos_mat_t128.npy", d_temp);
    convertDoubleToFloat16(d_temp, data);
    //aoba::LoadArrayFromNumpy("Data/Params/inv_cos_mat.npy", f_temp);
    //convertFloat32ToFloat16(f_temp, data);
    mLtcMInv = Texture::create2D(64, 64, ResourceFormat::RGBA16Float, 1, 1, data.data(), Resource::BindFlags::ShaderResource);

    // Load LTC coefficients
    aoba::LoadArrayFromNumpy("Data/Params/cos_coeff_t128.npy", d_temp);
    convertDoubleToFloat16(d_temp, data);
    //aoba::LoadArrayFromNumpy("Data/Params/cos_coeff.npy", f_temp);
    //convertFloat32ToFloat16(f_temp, data);
    mLtcCoeff = Texture::create2D(64, 64, ResourceFormat::R16Float, 1, 1, data.data(), Resource::BindFlags::ShaderResource);

    // Load LTSH matrices for N=4
    aoba::LoadArrayFromNumpy("Data/Params/inv_sh_mat_n4_t128.npy", d_temp);
    convertDoubleToFloat16(d_temp, data);
    //aoba::LoadArrayFromNumpy("Data/Params/inv_sh_n4_mat.npy", f_temp);
    //convertFloat32ToFloat16(f_temp, data);
    mLtshMInv = Texture::create2D(64, 64, ResourceFormat::RGBA16Float, 1, 1, data.data(), Resource::BindFlags::ShaderResource);

    // Load LTSH coefficients for N=4
    aoba::LoadArrayFromNumpy("Data/Params/sh_coeff_n4_t128.npy", d_temp);
    convertLtshCoeff(d_temp, data);
    //aoba::LoadArrayFromNumpy("Data/Params/sh_n4_coeff.npy", f_temp);
    //convertLtshCoeff(f_temp, data);
    mLtshCoeff = Texture::create2D(64 * 7, 64, ResourceFormat::RGBA16Float, 1, 1, data.data(), Resource::BindFlags::ShaderResource);

    // Load LTSH matrices for N=2
    aoba::LoadArrayFromNumpy("Data/Params/inv_sh_mat_n2_t128.npy", d_temp);
    convertDoubleToFloat16(d_temp, data);
    //aoba::LoadArrayFromNumpy("Data/Params/inv_sh_n2_mat.npy", f_temp);
    //convertFloat32ToFloat16(f_temp, data);
    mLtshMInvN2 = Texture::create2D(64, 64, ResourceFormat::RGBA16Float, 1, 1, data.data(), Resource::BindFlags::ShaderResource);

    // Load LTSH coefficients for N=2
    aoba::LoadArrayFromNumpy("Data/Params/sh_coeff_n2_t128.npy", d_temp);
    convertLtshCoeffN2(d_temp, data);
    //aoba::LoadArrayFromNumpy("Data/Params/sh_n2_coeff.npy", f_temp);
    //convertLtshCoeffN2(f_temp, data);
    mLtshCoeffN2 = Texture::create2D(64 * 3, 64, ResourceFormat::RGBA16Float, 1, 1, data.data(), Resource::BindFlags::ShaderResource);

    // Create Sampler
    Sampler::Desc desc;
    desc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Linear).setAddressingMode(Sampler::AddressMode::Border, Sampler::AddressMode::Border, Sampler::AddressMode::Border);
    mSampler = Sampler::create(desc);

    // Load default model
    loadModelFromFile(skDefaultModel, pSample->getCurrentFbo().get());
}

// Function to move camera back and forth between start and end points with given camera targets
void cameraReel(uint64_t frameID, Camera::SharedPtr camera) {
    glm::vec3 startPos = glm::vec3(-1.488, 1.198, 1.764);
    glm::vec3 startTarget = glm::vec3(-0.946, 0.905, 0.977);
    glm::vec3 endPos = glm::vec3(-0.519, 0.567, 2.371);
    glm::vec3 endTarget = glm::vec3(-0.272, 0.442, 1.410);

    auto posDiff = endPos - startPos;
    auto targetDiff = endTarget - startTarget;
    auto pos = startPos + posDiff * (sin(frameID / 100.f) + 1) * 0.5f;
    auto target = startTarget + targetDiff * (sin(frameID / 100.f) + 1) * 0.5f;
    camera->setPosition(pos);
    camera->setTarget(target);
}


void SimpleDeferred::onFrameRender(SampleCallbacks* pSample, RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo)
{
    GraphicsState* pState = pRenderContext->getGraphicsState().get();

    const glm::vec4 clearColor(0.38f, 0.52f, 0.10f, 1);

    if (mInitTextures)
    {
        mpLightingVars->setTexture("gLtcMinv", mLtcMInv);
        mpLightingVars->setTexture("gLtcCoeff", mLtcCoeff); 
        mpLightingVars->setTexture("gLtshMinv", mLtshMInv);
        mpLightingVars->setTexture("gLtshCoeff", mLtshCoeff);
        mpLightingVars->setTexture("gLtshMinvN2", mLtshMInvN2);
        mpLightingVars->setTexture("gLtshCoeffN2", mLtshCoeffN2);
        mpLightingVars->setSampler("gSampler", mSampler);
        mInitTextures = false;
    }

    // G-Buffer pass
    if(mpModel)
    {
        pRenderContext->clearFbo(mpGBufferFbo.get(), glm::vec4(0), 1.0f, 0, FboAttachmentType::Color | FboAttachmentType::Depth);
        pState->setFbo(mpGBufferFbo);

        cameraReel(pSample->getFrameID(), mpCamera);

        mpCamera->setDepthRange(mNearZ, mFarZ);
        CameraController& ActiveController = getActiveCameraController();
        ActiveController.update();

        // Animate
        if(mAnimate)
        {
            PROFILE("animate");
            mpModel->animate(pSample->getCurrentTime());
        }

        // Set render state
        pState->setRasterizerState(mpCullRastState[mCullMode]);
        pState->setDepthStencilState(mpDepthTestDS);

        // Render model
        mpModel->bindSamplerToMaterials(mpLinearSampler);
        pRenderContext->setGraphicsVars(mpDeferredVars);

        // Set Light Polygon 
        ConstantBuffer::SharedPtr pDefferedCB = mpDeferredVars["PolygonData"];
        mpAreaLight->setPolygonIntoDeferred(pDefferedCB.get());

        PROFILE("DeferredPass");

        pState->setProgram(mpDeferredPassProgram);
        ModelRenderer::render(pRenderContext, mpModel, mpCamera.get());
    }

    // Lighting pass (fullscreen quad)
    {
        pState->setFbo(pTargetFbo);
        pRenderContext->clearFbo(pTargetFbo.get(), clearColor, 1.0f, 0, FboAttachmentType::Color);

        // Reset render state
        pState->setRasterizerState(mpCullRastState[0]);
        pState->setBlendState(mpOpaqueBS);
        pState->setDepthStencilState(mpNoDepthDS);

        // Set lighting params
        ConstantBuffer::SharedPtr pLightCB = mpLightingVars["PerImageCB"];
        pLightCB["gAmbient"] = mAmbientIntensity;
        mpDirLight->setIntoProgramVars(mpLightingVars.get(), pLightCB.get(), "gDirLight");
        mpPointLight->setIntoProgramVars(mpLightingVars.get(), pLightCB.get(), "gPointLight");
        mpAreaLight->setIntoProgramVars(mpLightingVars.get(), pLightCB.get(), "gAreaLight");
        mpAreaLight->setPolygonIntoLighting(pLightCB.get(), "gAreaLightPosW");

        // create new samples if the area light render mode changed to ground truth, stop sample creation if render mode is not ground truth
        if ((mAreaLightRenderMode == AreaLightRenderMode::GroundTruth || mAreaLightRenderMode == AreaLightRenderMode::LtcBrdf || mAreaLightRenderMode == AreaLightRenderMode::LtshBrdf) && !mpAreaLight->getSampleCreation())
        {
            mpAreaLight->setSampleCreation(true);
        } 
        else if (!(mAreaLightRenderMode == AreaLightRenderMode::GroundTruth || mAreaLightRenderMode == AreaLightRenderMode::LtcBrdf || mAreaLightRenderMode == AreaLightRenderMode::LtshBrdf) && mpAreaLight->getSampleCreation())
        {
            mpAreaLight->setSampleCreation(false);
        }

        if (mAreaLightRenderMode == AreaLightRenderMode::GroundTruth || mAreaLightRenderMode == AreaLightRenderMode::LtcBrdf || mAreaLightRenderMode == AreaLightRenderMode::LtshBrdf)
        {
            ConstantBuffer::SharedPtr pSampleCB[4] = { mpLightingVars["SampleCB0"], mpLightingVars["SampleCB1"], mpLightingVars["SampleCB2"], mpLightingVars["SampleCB3"] };
            std::string varNames[4] = { "lightSamples0", "lightSamples1", "lightSamples2", "lightSamples3" };

            for (int i = 0; i < 4; i++)
            {
                mpAreaLight->setSamplesIntoProgramVars(pSampleCB[i].get(), varNames[i], i);
            }
        } 

        // Set camera position
        pLightCB->setVariable("gCamPosW", mpCamera->getPosition());
        
        // Debug mode
        pLightCB->setVariable("gDebugMode", (uint32_t)mDebugMode);

        // Area light render mode
        pLightCB->setVariable("gAreaLightRenderMode", (uint32_t)mAreaLightRenderMode);

        pLightCB->setVariable("gSeed", static_cast<float>(rand()) / (static_cast<float>(RAND_MAX) / 10000000.f));

        // Set GBuffer as input
        mpLightingVars->setTexture("gGBuf0", mpGBufferFbo->getColorTexture(0));
        mpLightingVars->setTexture("gGBuf1", mpGBufferFbo->getColorTexture(1));
        mpLightingVars->setTexture("gGBuf2", mpGBufferFbo->getColorTexture(2));
        mpLightingVars->setTexture("gGBuf3", mpGBufferFbo->getColorTexture(3));

        PROFILE("LightingPass");

        // Kick it off
        pRenderContext->setGraphicsVars(mpLightingVars);
        mpLightingPass->execute(pRenderContext);
    }

    auto tempTarget = mpCamera->getTarget();
    auto tempPos = mpCamera->getPosition();

    if (mSaveNextFrame) {
        if (mScreenshotFbo.get() == nullptr) {
            auto desc = pTargetFbo->getDesc();
            desc.setColorTarget(0, ResourceFormat::RGBA32Float);
            mScreenshotFbo = FboHelper::create2D(pTargetFbo->getWidth(), pTargetFbo->getHeight(), desc);
        }
        pState->setFbo(mScreenshotFbo);
        pRenderContext->clearFbo(mScreenshotFbo.get(), clearColor, 1.0f, 0, FboAttachmentType::Color);
        mpLightingPass->execute(pRenderContext);

        // save newly rendered HDR image
        auto frame = mScreenshotFbo->getColorTexture(0).get();
        frame->captureToFile(0, 0, "screenshot" + std::to_string(mSaveCount) + ".exr", Falcor::Bitmap::FileFormat::ExrFile);

        // save png
        auto png_frame = pTargetFbo->getColorTexture(0).get();
        png_frame->captureToFile(0, 0, "screenshot" + std::to_string(mSaveCount) + ".png");
        mSaveNextFrame = false;
        mSaveCount++;
    }
}

void SimpleDeferred::onShutdown(SampleCallbacks* pSample)
{
    mpModel.reset();
}

bool SimpleDeferred::onKeyEvent(SampleCallbacks* pSample, const KeyboardEvent& keyEvent)
{
    bool bHandled = getActiveCameraController().onKeyEvent(keyEvent);
    if(bHandled == false)
    {
        if(keyEvent.type == KeyboardEvent::Type::KeyPressed)
        {
            switch(keyEvent.key)
            {
            case KeyboardEvent::Key::R:
                resetCamera();
                break;
            case KeyboardEvent::Key::K:
                mSaveNextFrame = true;
                break;
            default:
                bHandled = false;
            }
        }
    }
    return bHandled;
}

bool SimpleDeferred::onMouseEvent(SampleCallbacks* pSample, const MouseEvent& mouseEvent)
{
    return getActiveCameraController().onMouseEvent(mouseEvent);
}

void SimpleDeferred::onResizeSwapChain(SampleCallbacks* pSample, uint32_t width, uint32_t height)
{
    mpCamera->setFocalLength(21.0f);
    mAspectRatio = (float(width) / float(height));
    mpCamera->setAspectRatio(mAspectRatio);
    // create G-Buffer
    const glm::vec4 clearColor(0.f, 0.f, 0.f, 0.f);
    Fbo::Desc fboDesc;
    fboDesc.setColorTarget(0, Falcor::ResourceFormat::RGBA16Float)
        .setColorTarget(1, Falcor::ResourceFormat::RGBA16Float)
        .setColorTarget(2, Falcor::ResourceFormat::RGBA16Float)
        .setColorTarget(3, Falcor::ResourceFormat::RGBA16Float)
        .setDepthStencilTarget(Falcor::ResourceFormat::D32Float);
    mpGBufferFbo = FboHelper::create2D(width, height, fboDesc);
}

void SimpleDeferred::resetCamera()
{
    if(mpModel)
    {
        // update the camera position
        float radius = mpModel->getRadius();
        //const glm::vec3& target = mpAreaLight->getPosition();
        const glm::vec3& target = glm::vec3(-0.5129f, 0.3637f, 1.7148f);
        glm::vec3 camPos = glm::vec3(-.6603f, .715f, 2.6394f);

        // set camera
        mpCamera->setPosition(camPos);
        mpCamera->setTarget(target);
        mpCamera->setUpVector(glm::vec3(0, 1, 0));
        mCameraType = FirstPersonCamera;

        // Update the controllers
        mModelViewCameraController.setModelParams(target, radius * 0.1f, 0.4f);
        mFirstPersonCameraController.setCameraSpeed(radius*0.25f);
        mNearZ = std::max(0.1f, mpModel->getRadius() / 750.0f);
        mFarZ = radius * 10;
    }
}

int main(int argc, char** argv)
{
    SimpleDeferred::UniquePtr pRenderer = std::make_unique<SimpleDeferred>();
    SampleConfig config;
    config.windowDesc.width = 1280;
    config.windowDesc.height = 720;
    config.windowDesc.resizableWindow = true;
    config.windowDesc.title = "Simple Deferred";
    config.argc = (uint32_t)argc;
    config.argv = argv;
    Sample::run(config, pRenderer);
    return 0;
}
