#pragma once
#include <Falcor.h>
#include <Graphics/Light.h>
#include <Data/HostDeviceSharedMacros.h>

using namespace Falcor;

class SimpleAreaLight : public Light, public std::enable_shared_from_this<SimpleAreaLight>
{
public:
    using SharedPtr = std::shared_ptr<SimpleAreaLight>;
    using SharedConstPtr = std::shared_ptr<const SimpleAreaLight>;

    static SharedPtr create();

    SimpleAreaLight();
    ~SimpleAreaLight();

    /** Set light source scaling
        \param[in] scale x,y,z scaling factors
    */
    void setScaling(vec3 scale) { mScaling = scale; update(); }

    /** Set light source scale
      */
    vec3 getScaling() const { return mScaling; }

    /** Get total light power (needed for light picking)
    */
    float getPower() const override;

	/** Get the transformed vertices.
	*/
	std::vector<glm::vec3> getTransformedVertices() { return mTransformedVertices3d; }

    /** Set transform matrix
        \param[in] mtx object to world space transform matrix
    */
    void setTransformMatrix(const glm::mat4& mtx) { mTransformMatrix = mtx; update(); }

	/** Set vertices of area light polygon (must be closed and without crossings, speciefied in CCW order)
		\param[in] vertices of the polygon in 2D-XY space
	*/
	void setVertices2d(const std::vector<glm::vec2>& vertices) { mVertices2d = vertices; update(); }

    /** Get transform matrix
    */
    glm::mat4 getTransformMatrix() const { return mTransformMatrix; }

    /** Set the light intensity.
        \param[in] intensity Vec3 corresponding to RGB intensity
    */
    void setIntensity(const glm::vec3& intensity) { mData.intensity = intensity; update(); }

    /** Render UI elements for this light.
        \param[in] pGui The GUI to create the elements with
        \param[in] group Optional. If specified, creates a UI group to display elements within
    */
    void renderUI(Gui* pGui, const char* group = nullptr) override;

    /** IMovableObject interface
    */
    void move(const glm::vec3& position, const glm::vec3& target, const glm::vec3& up) override;

private:
    void update();

	// since we only support planar polygons they must be specified in 2d (x, y) and later be translated
    std::vector<glm::vec2> mVertices2d;
	std::vector<glm::vec3> mTransformedVertices3d;
	size_t mNumVertices;
    glm::mat4 mTransformMatrix;
    glm::vec3 mScaling;
};