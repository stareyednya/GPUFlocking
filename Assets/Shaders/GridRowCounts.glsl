#version 430 core

uniform uvec2 cellCounts;
uniform int cellCount;

layout(std430, binding = 5) buffer Boid_Counts
{
	uint boid_counts[];
};

layout(std430, binding = 6) buffer BoidOffsets // currently going to be build as relative offsets
{
	uint boid_offsets[];
};

layout(std430, binding = 9) buffer GridRowCounts
{
	uint row_counts[];
};

layout( local_size_x = 128, local_size_y = 1, local_size_z = 1 ) in; /// ???

void main()
{
	// go through a full row of cells in a for loop per thread 
	uint i = gl_GlobalInvocationID.x * cellCounts.x; // index to start from
	
	uint rollingOffset = 0;
	for (; i < i + cellCounts.x; i++)
	{
		boid_offsets[i] = rollingOffset;
		rollingOffset += boid_counts[i];
	}

	row_counts[i] = rollingOffset;
}