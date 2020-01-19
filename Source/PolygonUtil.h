#pragma once

// Code taken from https://www.geeksforgeeks.org/how-to-check-if-a-given-point-lies-inside-a-polygon/

#include "Falcor.h"

class PolygonUtil
{
public:
	/** Given three colinear points p, q, r, the function checks if point q lies on line segment 'pr' 
	*/
	static bool onSegment(const glm::vec2 &p, const glm::vec2 &q, const glm::vec2 &r);

	/** To find orientation of ordered triplet(p, q, r).
		The function returns following values 
		0 --> p, q and r are colinear 
		1 --> Clockwise 
		2 --> Counterclockwise 
	*/
	static int orientation(const glm::vec2 &p, const glm::vec2 &q, const glm::vec2 &r);

	/** The function that returns true if line segment 'p1q1' and 'p2q2' intersect. 
	*/
	static bool doIntersect(const glm::vec2 &p1, const glm::vec2 &q1, const glm::vec2 &p2, const glm::vec2 &q2);

	/** Returns true if the point p lies inside the polygon[] with n vertices
	*/
	static bool isInside(const std::vector<glm::vec2>& polygon, int n, const glm::vec2& p);
};

