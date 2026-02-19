/*
* Author: Chris Campbell - www.iforce2d.net
*
* Copyright (c) 2006-2011 Erin Catto http://www.box2d.org
*
* This software is provided 'as-is', without any express or implied
* warranty.  In no event will the authors be held liable for any damages
* arising from the use of this software.
* Permission is granted to anyone to use this software for any purpose,
* including commercial applications, and to alter it and redistribute it
* freely, subject to the following restrictions:
* 1. The origin of this software must not be misrepresented; you must not
* claim that you wrote the original software. If you use this software
* in a product, an acknowledgment in the product documentation would be
* appreciated but is not required.
* 2. Altered source versions must be plainly marked as such, and must not be
* misrepresented as being the original software.
* 3. This notice may not be removed or altered from any source distribution.
*/

#ifndef IFORCE2D_ONEWAYWALLS_H
#define IFORCE2D_ONEWAYWALLS_H

#ifndef DEGTORAD
#define DEGTORAD 0.0174532925199432957f
#define RADTODEG 57.295779513082320876f
#endif

class iforce2d_OneWayWalls : public Test
{
public:
    iforce2d_OneWayWalls()
    {
        b2BodyDef groundBodyDef;
        b2Body* groundBody = m_world->CreateBody(&groundBodyDef);

        {//boundary fence
            b2PolygonShape polygonShape;
            polygonShape.SetAsBox( 20, 1, b2Vec2(0, 0), 0);//ground
            groundBody->CreateFixture(&polygonShape, 0);
            polygonShape.SetAsBox( 20, 1, b2Vec2(0, 40), 0);//ceiling
            //groundBody->CreateFixture(&polygonShape, 0);
            polygonShape.SetAsBox( 1, 20, b2Vec2(-20, 20), 0);//left wall
            groundBody->CreateFixture(&polygonShape, 0);
            polygonShape.SetAsBox( 1, 20, b2Vec2(20, 20), 0);//right wall
            groundBody->CreateFixture(&polygonShape, 0);
        }

        //setup platform shape for reuse
        b2PolygonShape polygonShape;
        b2Vec2 verts[5];
        verts[0].Set(   0, -0.75);
        verts[1].Set( 2.5, -0.5 );
        verts[2].Set( 2.5,  0.5 );
        verts[3].Set(-2.5,  0.5 );
        verts[4].Set(-2.5, -0.5);
        polygonShape.Set( verts, 5 );

        b2FixtureDef fixtureDef;
        fixtureDef.shape = &polygonShape;
        fixtureDef.density = 1;

        //static platforms
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_staticBody;
            bodyDef.position.Set(0,7.55);
            m_world->CreateBody(&bodyDef)->CreateFixture( &polygonShape, 0 )->SetUserData((void*)1);//anything non-zero
            bodyDef.position.Set(-10,7.5);
            m_world->CreateBody(&bodyDef)->CreateFixture( &polygonShape, 0 )->SetUserData((void*)1);//anything non-zero
        }

        //kinematic platform
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_kinematicBody;
            bodyDef.position.Set(0,10);
            m_platformBody = m_world->CreateBody(&bodyDef);
            b2Fixture* platformFixture = m_platformBody->CreateFixture( &polygonShape, 0 );
            platformFixture->SetUserData((void*)1);//anything non-zero
        }

        //kinematic platform 2
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_kinematicBody;
            bodyDef.position.Set(0,15);
            m_platformBody2 = m_world->CreateBody(&bodyDef);
            b2Fixture* platformFixture2 = m_platformBody2->CreateFixture( &polygonShape, 0 );
            platformFixture2->SetUserData((void*)1);//anything non-zero
        }

        //dynamic swinging wall
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(10,15);
            b2Body* swingingBody = m_world->CreateBody(&bodyDef);
            b2Fixture* swingingFixture = swingingBody->CreateFixture( &polygonShape, 1 );
            swingingFixture->SetUserData((void*)1);//anything non-zero

            b2RevoluteJointDef jointDef;
            jointDef.bodyA = groundBody;
            jointDef.bodyB = swingingBody;
            jointDef.localAnchorA.Set( 12.25, 15 );
            jointDef.localAnchorB.Set(  2.25, 0 );
            m_world->CreateJoint( &jointDef );
        }

        //free roaming dynamic one-way wall
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(-10,15);
            b2Body* freeBody = m_world->CreateBody(&bodyDef);
            freeBody->SetTransform( freeBody->GetPosition(), 180*DEGTORAD );//prevent fall through floor at start
            b2Fixture* freeFixture = freeBody->CreateFixture( &polygonShape, 1 );
            freeFixture->SetUserData((void*)1);//anything non-zero
        }

        //little box
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(0,8.6);
            b2Body* body = m_world->CreateBody(&bodyDef);

            polygonShape.SetAsBox( 0.5, 0.5 );
            m_world->CreateBody( &bodyDef )->CreateFixture( &polygonShape, 1 );
        }
    }

    void BeginContact(b2Contact* contact)
    {
        b2Fixture* fixtureA = contact->GetFixtureA();
        b2Fixture* fixtureB = contact->GetFixtureB();

        //check if one of the fixtures is the platform
        b2Fixture* platformFixture = NULL;
        b2Fixture* otherFixture = NULL;
        if ( fixtureA->GetUserData() ) {
            platformFixture = fixtureA;
            otherFixture = fixtureB;
        }
        else if ( fixtureB->GetUserData() ) {
            platformFixture = fixtureB;
            otherFixture = fixtureA;
        }

        if ( !platformFixture )
            return;

        int numPoints = contact->GetManifold()->pointCount;
        b2WorldManifold worldManifold;
        contact->GetWorldManifold( &worldManifold );

        b2Body* platformBody = platformFixture->GetBody();
        b2Body* otherBody = otherFixture->GetBody();

        //check if contact points are moving into platform
        for (int i = 0; i < numPoints; i++) {

            b2Vec2 pointVelPlatform =
                platformBody->GetLinearVelocityFromWorldPoint( worldManifold.points[i] );
            b2Vec2 pointVelOther =
                otherBody->GetLinearVelocityFromWorldPoint( worldManifold.points[i] );
            b2Vec2 relativeVel = platformBody->GetLocalVector( pointVelOther - pointVelPlatform );

            if ( relativeVel.y < -1 ) //if moving down faster than 1 m/s, handle as before
                return;//point is moving into platform, leave contact solid and exit
            else if ( relativeVel.y < 1 ) { //if moving slower than 1 m/s
                //borderline case, moving only slightly out of platform
                b2Vec2 relativePoint = platformBody->GetLocalPoint( worldManifold.points[i] );
                float platformFaceY = 0.5f;//front of platform, from fixture definition :(
                if ( relativePoint.y > platformFaceY - 0.05 )
                    return;//contact point is less than 5cm inside front face of platfrom
            }
        }

        //no points are moving into platform, contact should not be solid
        contact->SetEnabled(false);
    }

    void EndContact(b2Contact* contact)
    {
        contact->SetEnabled(true);
    }

    void Step(Settings* settings)
    {
        //move platforms
        float theta = 0.025 * m_stepCount;
        {
            b2Vec2 targetPos( 0 + 2 * sinf(theta), 10 + 2.55 * cosf(theta) );
            m_platformBody->SetLinearVelocity( 60 * (targetPos - m_platformBody->GetPosition()));
        }
        {
            b2Vec2 targetPos( 0 - 0 * sinf(theta), 15 - 2.55 * cosf(theta) );
            m_platformBody2->SetLinearVelocity( 60 * (targetPos - m_platformBody2->GetPosition()));
        }

        Test::Step(settings);
    }

    static Test* Create()
    {
        return new iforce2d_OneWayWalls;
    }

    b2Body* m_platformBody;
    b2Body* m_platformBody2;

};

#endif
