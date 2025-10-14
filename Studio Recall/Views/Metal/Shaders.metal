//
//  Shaders.metal
//  Studio Recall
//
//  Metal shaders for high-performance canvas rendering
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Data Structures

struct Vertex {
	float2 position [[attribute(0)]];
	float2 texCoord [[attribute(1)]];
};

struct InstanceData {
	float4x4 modelMatrix;
	float4 texCoordRect;  // x, y, width, height in atlas
	float alpha;
};

struct Uniforms {
	float4x4 projectionMatrix;
	float4x4 viewMatrix;
};

struct VertexOut {
	float4 position [[position]];
	float2 texCoord;
	float alpha;
};

// MARK: - Vertex Shader

vertex VertexOut vertexShader(
	Vertex in [[stage_in]],
	constant Uniforms &uniforms [[buffer(1)]],
	constant InstanceData *instances [[buffer(2)]],
	uint instanceID [[instance_id]]
) {
	VertexOut out;

	// Get instance data
	InstanceData instance = instances[instanceID];

	// Transform position
	float4 worldPosition = instance.modelMatrix * float4(in.position, 0.0, 1.0);
	float4 viewPosition = uniforms.viewMatrix * worldPosition;
	out.position = uniforms.projectionMatrix * viewPosition;

	// Map texture coordinates from atlas
	// Flip V coordinate because CoreGraphics is bottom-up but Metal textures are top-down
	float2 flippedTexCoord = float2(in.texCoord.x, 1.0 - in.texCoord.y);
	out.texCoord = instance.texCoordRect.xy + flippedTexCoord * instance.texCoordRect.zw;
	out.alpha = instance.alpha;

	return out;
}

// MARK: - Fragment Shader

fragment float4 fragmentShader(
	VertexOut in [[stage_in]],
	texture2d<float> texture [[texture(0)]],
	sampler textureSampler [[sampler(0)]]
) {
	float4 color = texture.sample(textureSampler, in.texCoord);
	color.a *= in.alpha;
	return color;
}
