#version 430 core

uniform float sepDis;
uniform float alignDis;
uniform float cohDis;

uniform float sepWeight;
uniform float alignWeight;
uniform float cohWeight;
uniform float avoidWeight;

uniform float maxSpeed;
uniform float maxForce;

uniform float dt;

uniform float maxSeeAhead;
uniform int noOfObstacles;

uniform int numBoids;
uniform float ratio;
uniform uvec2 cellCounts;
uniform int cellCount;

struct flock_member
{
	vec3 pos;
	float angle;
	vec3 vel;
	float groupNo;
	vec3 accel;
	float scrap3;
};

struct obstacle
{
	vec3 centre;
	float radius;
};

layout(std140, binding = 0) buffer Flock_In
{
	flock_member input_flock[];
};

layout(std140, binding = 1) buffer Flock_Out
{
	flock_member output_flock[];
};

layout(std140, binding = 2) buffer Obstacles
{
	obstacle obstacles[];
};

layout(std140, binding = 5) buffer BoidCounts
{
	uint boid_counts[];
};

layout(std140, binding = 6) buffer BoidOffsets
{
	uint boid_offsets[];
};

layout(std140, binding = 8) buffer BoidIndex
{
	uint boid_indexes[];
};

layout( local_size_x = 128, local_size_y = 1, local_size_z = 1 ) in;

vec3 Limit(vec3 v, float m)
{
	float lengthSqr = v.x * v.x + v.y * v.y + v.z * v.z;

	if (lengthSqr > m*m && lengthSqr > 0.0)
	{
		float ls = sqrt(lengthSqr);
		float ratio = m / ls;
		v *= ratio;
	}
	return v;
}

vec3 Seek(vec3 pos, vec3 vel, vec3 target)
{
	vec3 desired = target;
	desired -= pos; 
	desired = normalize(desired); 
	desired *= maxSpeed;
	uint gid = gl_GlobalInvocationID.x;
	output_flock[gid].accel = desired - vel;
	Limit(output_flock[gid].accel, maxForce);
	return output_flock[gid].accel;
}

vec3 Separation(vec3 pos, vec3 vel, float groupNo, flock_member otherBoid, inout int count)
{
	vec3 steering = vec3(0, 0, 0);

	vec3 otherPos = otherBoid.pos;

	float d = abs(distance(pos, otherPos));

	float dis = groupNo == otherBoid.groupNo ? sepDis : sepDis + 30;

	if (d < dis && d > 0.0)
	{
		vec3 diff = vec3(0, 0, 0);
		diff = pos - otherPos;
		diff = normalize(diff);
		diff /= d;
		steering += diff;
		count += 1;
	}

	return steering;
}

vec3 Separation(vec3 pos, vec3 vel, float groupNo)
{
	uint localID = gl_LocalInvocationID.x;

	vec3 steering = vec3(0.0,0.0,0.0);
	float count = 0.0;

	for (uint i = 0; i < gl_NumWorkGroups.x; i++)
	{
		for (int j = 0; j < gl_WorkGroupSize.x; j++)
		{
			vec3 otherPos = input_flock[i * gl_WorkGroupSize.x + j].pos;
			if (i * gl_WorkGroupSize.x + j != gl_GlobalInvocationID.x)
			{
				float d = abs(distance(pos, otherPos));

				float dis = groupNo == input_flock[i * gl_WorkGroupSize.x + j].groupNo ? sepDis : sepDis + 30;

				if (d < dis && d > 0.0)
				{
					vec3 diff = vec3(0, 0, 0);
					diff = pos - otherPos;
					diff = normalize(diff);
					diff /= d;
					steering += diff;
					count += 1.0;
				}
			}
			
		}
		
	}	


	if (count > 0.0)
	{
		steering /= count;
	}

	if(length(steering) > 0.0)
	{
		steering = normalize(steering);
		steering *= maxSpeed;
		steering -= vel;
		steering = Limit(steering, maxForce);
	}

	return steering;
}

vec3 Alignment(vec3 pos, vec3 vel, flock_member otherBoid, inout int alignCount)
{
	vec3 otherPos = otherBoid.pos;
	vec3 sum = vec3(0.0, 0.0, 0.0);
	float d = abs(distance(pos, otherPos));

	if (d < alignDis && d > 0.0)
	{
		sum += otherBoid.vel;
		alignCount += 1;
	}

	return sum;
}

vec3 Alignment(vec3 pos, vec3 vel)
{
	uint localID = gl_LocalInvocationID.x;

	vec3 sum = vec3(0.0,0.0,0.0);
	float count = 0.0;

	for (uint i = 0; i < gl_NumWorkGroups.x; i++)
	{
		for (int j = 0; j < gl_WorkGroupSize.x; j++)
		{
			vec3 otherPos = input_flock[i * gl_WorkGroupSize.x + j].pos;
			if (i * gl_WorkGroupSize.x + j != gl_GlobalInvocationID.x)
			{
				float d = abs(distance(pos, otherPos));

				if (d < alignDis && d > 0.0)
				{
					sum += input_flock[i * gl_WorkGroupSize.x + j].vel;
					count += 1.0;
				}
			}
		}
	}

	if (count > 0.0)
	{
		sum /= count;
		sum = normalize(sum);
		sum *= maxSpeed;

		vec3 steering = sum - vel;
		steering = Limit(steering, maxForce);

		return steering;
	}
	else
	{
		return vec3(0.0,0.0,0.0);
	}
}

vec3 Cohesion(vec3 pos, vec3 vel, flock_member otherBoid, inout int cohCount)
{
	vec3 steering = vec3(0.0, 0.0, 0.0);
	vec3 otherPos = otherBoid.pos;

	float d = abs(distance(pos, otherPos));

	if (d < cohDis && d > 0.0)
	{
		steering += otherPos;
		cohCount += 1;
	}

	return steering;
}

vec3 Cohesion(vec3 pos, vec3 vel)
{
	uint localID = gl_LocalInvocationID.x;

	vec3 steering = vec3(0.0,0.0,0.0);
	float count = 0.0;
	for (uint i = 0; i < gl_NumWorkGroups.x; i++)
	{
		for (int j = 0; j < gl_WorkGroupSize.x; j++)
		{
			vec3 otherPos = input_flock[i * gl_WorkGroupSize.x + j].pos;
			if (i * gl_WorkGroupSize.x + j != gl_GlobalInvocationID.x)
			{
				float d = abs(distance(pos, otherPos));

				if (d < cohDis && d > 0.0)
				{
					steering += otherPos;
					count += 1.0;
				}
			}
		}
	}

	if(count > 0.0)
	{
		steering /= count;
		return Seek(pos, vel, steering);
	}
	else
	{
		return vec3(0.0,0.0,0.0);
	}
}

bool LineCircleIntersect(vec3 ahead, vec3 ahead2, obstacle nextOb, vec3 pos)
{
	vec3 dis = nextOb.centre - ahead;
	vec3 dis2 = nextOb.centre - ahead2;
	vec3 posDis = nextOb.centre - pos;

	return length(dis) <= nextOb.radius
		|| length(dis2) <= nextOb.radius
		|| length(posDis) <= nextOb.radius;
}

vec3 Avoidance(vec3 pos, vec3 vel)
{

	vec3 steering = vec3(0.0, 0.0, 0.0);

	// ahead = position + normalize(velocity) * MAX_SEE_AHEAD
	// calculate the ahead vector
	vec3 tempVel = normalize(vel);
	vec3 ahead = pos + tempVel * maxSeeAhead;
	// calculate the ahead2 vector
	vec3 ahead2 = pos + tempVel * maxSeeAhead * 0.5;

	// find the most threatening obstacle - working on index checks
	int mostThreateningObstacle = -1;
	for (int i = 0; i < noOfObstacles; i++)
	{
		obstacle nextOb = obstacles[i];
		bool collision = LineCircleIntersect(ahead, ahead2, nextOb, pos);
		float obDis = distance(pos, nextOb.centre);
		float threatDis = 0;
		if (mostThreateningObstacle > -1)
			threatDis = distance(pos, obstacles[mostThreateningObstacle].centre);

		if (collision && (mostThreateningObstacle == -1 || obDis < threatDis))
			mostThreateningObstacle = i;
	}

	if (mostThreateningObstacle > -1)
	{
		steering = ahead - obstacles[mostThreateningObstacle].centre;
		steering = Limit(steering, maxForce);
	}

	return steering;
}



vec3 ApplyForce(vec3 accel, vec3 force)
{
	return accel + force;
} 

float Angle(vec3 vel)
{
	vec3 tempVel = normalize(vel);
	return atan(tempVel.x, -tempVel.z);
	//return atan(tempVel.z, tempVel.x);
	//return atan(vel.x, vel.z) * 180 / 3.14;
}

vec3 Update(vec3 pos, vec3 vel, vec3 accel, float groupNo)
{
	uvec2 cell = uvec2(pos.xz * ratio);

	vec3 sep = vec3(0, 0, 0);
	int sepCount = 0;
	vec3 align = vec3(0, 0, 0);
	int alignCount = 0;
	vec3 coh = vec3(0, 0, 0);
	int cohCount = 0;

	for (int y = -1; y <= 1; ++y)
	{
		for (int x = -1; x <= 1; ++x)
		{
			uint cellNum = (cell.x + x + (cell.y + y) * cellCounts.x + cellCount) % cellCount;
			uint i = boid_offsets[cellNum];
			uint last = i + boid_counts[cellNum];

			for (; i < last; ++i)
			{
				flock_member otherBoid = input_flock[boid_indexes[i]];
				sep += Separation(pos, vel, groupNo, otherBoid, sepCount);
				align += Alignment(pos, vel, otherBoid, alignCount);
				coh += Cohesion(pos, vel, otherBoid, cohCount);
			}
		}
	}

	if (sepCount > 0.0)
	{
		sep /= sepCount;
	}

	if (length(sep) > 0.0)
	{
		sep = normalize(sep);
		sep *= maxSpeed;
		sep -= vel;
		sep = Limit(sep, maxForce);
	}

	if (alignCount > 0.0)
	{
		align /= alignCount;
		align = normalize(align);
		align *= maxSpeed;

		vec3 steering = align - vel;
		align = Limit(align, maxForce);
	}

	if (cohCount > 0.0)
	{
		coh /= cohCount;
		coh = Seek(pos, vel, coh);
	}

	sep *= sepWeight;
	align *= alignWeight;
	coh *= cohWeight;

	accel = ApplyForce(accel, sep);
	accel = ApplyForce(accel, align);
	accel = ApplyForce(accel, coh);

	accel *= 0.4;
	vel += accel * dt;
	Limit(vel, maxSpeed);


	return vel;

	/*vec3 sep = Separation(pos, vel, groupNo);
	vec3 align = Alignment(pos, vel);
	vec3 cohesion = Cohesion(pos, vel);
	vec3 avoidance = Avoidance(pos, vel);

	sep *= sepWeight;
	align *= alignWeight;
	cohesion *= cohWeight;
	avoidance *= avoidWeight;

	accel = ApplyForce(accel, sep);
	accel = ApplyForce(accel, align);
	accel = ApplyForce(accel, cohesion);
	accel = ApplyForce(accel, avoidance);

	accel *= 0.4;
	vel += accel * dt;
	Limit(vel, maxSpeed);

	return vel;*/

}


void main()
{
	uint gid = gl_GlobalInvocationID.x;

	if (gid >= numBoids) return;

	flock_member thisBoid = input_flock[gid];

	uvec2 cell = uvec2(thisBoid.pos.xz * ratio);

	vec3 newVel = Update(thisBoid.pos, thisBoid.vel, thisBoid.accel, thisBoid.groupNo);
	input_flock[gid].accel = vec3(0, 0, 0);
	output_flock[gid].accel = vec3(0, 0, 0);

	vec3 pos = thisBoid.pos;
	pos += newVel * dt;

	if (pos.x < -1010)
		pos.x += 2000;
	if (pos.z < -1010)
		pos.z += 2000;

	if (pos.x > 1010)
		pos.x -= 2000;
	if (pos.z > 1010)
		pos.z -= 2000;

	output_flock[gid].vel = newVel;
	output_flock[gid].pos = pos;

	output_flock[gid].angle = Angle(newVel);

	/*uint gid = gl_GlobalInvocationID.x;
	uint lid = gl_LocalInvocationID.x;
	flock_member thisMember = input_flock[gid];

	vec3 newVel = Update(thisMember.pos, thisMember.vel, thisMember.accel, thisMember.groupNo);
	input_flock[gid].accel = vec3(0,0,0);
	output_flock[gid].accel = vec3(0,0,0);

	vec3 pos = thisMember.pos;
	pos += newVel * dt;

	if (pos.x < -1010)
		pos.x += 2000;
	if (pos.z < -1010)
		pos.z += 2000;

	if (pos.x > 1010)
		pos.x -= 2000;
	if (pos.z > 1010)
		pos.z -= 2000;

	output_flock[gid].vel = newVel;
	output_flock[gid].pos = pos;

	output_flock[gid].angle = Angle(newVel);*/
}