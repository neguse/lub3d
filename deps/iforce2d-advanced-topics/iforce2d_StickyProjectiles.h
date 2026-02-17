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

#ifndef IFORCE2D_STICKY_PROJECTILES_H
#define IFORCE2D_STICKY_PROJECTILES_H

#ifndef DEGTORAD
#define DEGTORAD 0.0174532925199432957f
#define RADTODEG 57.295779513082320876f
#endif

#include <vector>

struct TargetParameters {
    float hardness;
};

struct StickyInfo {
    b2Body* arrowBody;
    b2Body* targetBody;
    bool operator<(StickyInfo other) const { return arrowBody < other.arrowBody; }
    bool operator==(StickyInfo other) { return arrowBody == other.arrowBody; }
};

bool g_showArrowGraphic = true;

class StickyProjectilesDebugDraw : public DebugDraw
{
public:
    void DrawSolidPolygon(const b2Vec2* vertices, int32 vertexCount, const b2Color& color)
    {
        if ( g_showArrowGraphic )
        {
            //a dirty little hack to tell which polygons are arrows... the small ones :)
            b2Vec2 localVertical = vertices[3] - vertices[1];
            if ( localVertical.Length() < 0.25f ) {
                float angle = b2Atan2( localVertical.y, localVertical.x );
                b2Vec2 bodyPosition = 0.5f * (vertices[3] + vertices[1]);
                glPushMatrix();
                glTranslatef(bodyPosition.x, bodyPosition.y, 0);
                glRotatef((angle*RADTODEG)+90, 0,0,1);
                glBegin(GL_LINES);
                //shaft
                glColor3f(1,0,0);
                glVertex2f( 0.2f, 0 );
                glColor3f(1,1,1);
                glVertex2f( -1.4f, 0 );
                //head
                glVertex2f( 0.6f, 0 );
                glVertex2f( 0.2f, 0.075f );
                glVertex2f( 0.6f, 0 );
                glVertex2f( 0.2f, -0.075f );
                glVertex2f( 0.2f, 0.075f );
                glVertex2f( 0.2f, -0.075f );
                //tail
                for (float x = -1.4f; x < -1.1f; x += 0.1f) {
                    glVertex2f( x, 0 );
                    glVertex2f( x-0.1f, 0.1f );
                    glVertex2f( x, 0 );
                    glVertex2f( x-0.1f, -0.1f );
                }
                glColor3f(1,0,0);
                for (float x = -1.35f; x < -1.1f; x += 0.1f) {
                    glVertex2f( x, 0 );
                    glVertex2f( x-0.1f, 0.1f );
                    glVertex2f( x, 0 );
                    glVertex2f( x-0.1f, -0.1f );
                }
                glEnd();
                glPopMatrix();
                return;
            }
        }

        DebugDraw::DrawSolidPolygon(vertices, vertexCount, color);
    }
};

StickyProjectilesDebugDraw spDebugDraw;

class iforce2d_StickyProjectiles : public Test
{
public:
    iforce2d_StickyProjectiles()
    {
        m_world->SetDebugDraw( &spDebugDraw );

        //were gonna need a larger area to play in for this one!
        b2FixtureDef fixtureDef;
        b2PolygonShape polygonShape;
        fixtureDef.shape = &polygonShape;
        polygonShape.SetAsBox( 50, 1, b2Vec2(0, 0), 0);//ground
        m_groundBody->CreateFixture(&fixtureDef)->SetUserData( &m_woodTarget );
        polygonShape.SetAsBox( 50, 1, b2Vec2(0, 100), 0);//ceiling
        m_groundBody->CreateFixture(&fixtureDef)->SetUserData( &m_woodTarget );
        polygonShape.SetAsBox( 1, 50, b2Vec2(-50, 50), 0);//left wall
        m_groundBody->CreateFixture(&fixtureDef)->SetUserData( &m_steelTarget );
        polygonShape.SetAsBox( 1, 50, b2Vec2(50, 50), 0);//right wall
        m_groundBody->CreateFixture(&fixtureDef)->SetUserData( &m_woodTarget );

        //launcher
        {
            b2BodyDef bodyDef;
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(-35, 5);
            m_launcherBody = m_world->CreateBody(&bodyDef);
            b2CircleShape circleShape;
            circleShape.m_radius = 2;
            fixtureDef.shape = &circleShape;
            fixtureDef.density = 1;
            b2Fixture* circleFixture = m_launcherBody->CreateFixture(&fixtureDef);

            //pin the circle in place
            b2RevoluteJointDef revoluteJointDef;
            revoluteJointDef.bodyA = m_groundBody;
            revoluteJointDef.bodyB = m_launcherBody;
            revoluteJointDef.localAnchorA.Set(-35,5);
            revoluteJointDef.localAnchorB.Set(0,0);
            revoluteJointDef.enableMotor = true;
            revoluteJointDef.maxMotorTorque = 250;
            revoluteJointDef.motorSpeed = 0;
            m_world->CreateJoint( &revoluteJointDef );
        }

        //targets, from closest to farthest
        {
            //common features
            b2PolygonShape polygonShape;
            polygonShape.SetAsBox( 0.5, 4 );
            b2FixtureDef fixtureDef;
            fixtureDef.density = 2;
            fixtureDef.shape = &polygonShape;

            //static straw target
            b2BodyDef bodyDef;
            bodyDef.type = b2_staticBody;
            bodyDef.position.Set(0, 5);
            bodyDef.angle = -10 * DEGTORAD;
            m_world->CreateBody( &bodyDef )->CreateFixture( &fixtureDef )->SetUserData( &m_strawTarget );

            //hanging wood target
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(15, 20);
            bodyDef.angle = 0;
            b2Body* woodTarget = m_world->CreateBody( &bodyDef );
            woodTarget->CreateFixture( &fixtureDef )->SetUserData( &m_woodTarget );

            //joint to hang the target from
            b2DistanceJointDef distanceJointDef;
            distanceJointDef.bodyA = m_groundBody;
            distanceJointDef.bodyB = woodTarget;
            distanceJointDef.localAnchorA.Set(15,25);
            distanceJointDef.localAnchorB.Set(0,3.5f);
            m_world->CreateJoint( &distanceJointDef );

            //another hanging wood target
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(25, 40);
            bodyDef.angle = 0;
            woodTarget = m_world->CreateBody( &bodyDef );
            woodTarget->CreateFixture( &fixtureDef )->SetUserData( &m_woodTarget );

            //joint for second hanging target
            distanceJointDef.bodyB = woodTarget;
            distanceJointDef.localAnchorA.Set(25,45);
            m_world->CreateJoint( &distanceJointDef );

            //vertically moving wood target
            bodyDef.type = b2_kinematicBody;
            bodyDef.position.Set(40, 50);
            m_kinematicBody = m_world->CreateBody( &bodyDef );
            m_kinematicBody->CreateFixture( &fixtureDef )->SetUserData( &m_woodTarget );

            //apple on top of moving target - good luck!
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(40, 54.75);
            b2CircleShape circleShape;
            circleShape.m_radius = 0.75f;
            fixtureDef.shape = &circleShape;
            fixtureDef.density = 10;//otherwise falling arrows knock it down too easily
            woodTarget = m_world->CreateBody( &bodyDef );
            woodTarget->CreateFixture( &fixtureDef )->SetUserData( &m_strawTarget );

        }

        m_useWeldJoint = true;
        m_launchSpeed = 50;

        m_strawTarget.hardness = 1;
        m_woodTarget.hardness = 5;
        m_steelTarget.hardness = 100;//never likely to stick

        loadOneArrow();

    }

    void loadOneArrow()
    {
        b2BodyDef bodyDef;
        bodyDef.type = b2_dynamicBody;
        bodyDef.position.Set( 0, 5 );

        b2PolygonShape polygonShape;
        b2Vec2 vertices[4];
        vertices[0].Set( -1.4f,     0 );
        vertices[1].Set(     0, -0.1f );
        vertices[2].Set(  0.6f,     0 );
        vertices[3].Set(     0,  0.1f );
        polygonShape.Set(vertices, 4);

        b2FixtureDef fixtureDef;
        fixtureDef.shape = &polygonShape;
        fixtureDef.density = 1;

        m_loadedArrowBody = m_world->CreateBody(&bodyDef);
        m_loadedArrowBody->CreateFixture( &fixtureDef );
        m_loadedArrowBody->SetAngularDamping( 3 );
        m_loadedArrowBody->SetGravityScale(0);//until fired
        //m_loadedArrowBody->SetBullet(true);
    }

    void Keyboard(unsigned char key)
    {
        switch (key) {
        case 'q' :
            m_loadedArrowBody->SetAwake(true);
            m_loadedArrowBody->SetGravityScale(1);
            m_loadedArrowBody->SetAngularVelocity(0);
            m_loadedArrowBody->SetTransform( m_launcherBody->GetWorldPoint( b2Vec2(3,0) ), m_launcherBody->GetAngle() );
            m_loadedArrowBody->SetLinearVelocity( m_launcherBody->GetWorldVector( b2Vec2(m_launchSpeed,0) ) );
            m_arrowBodies.push_back(m_loadedArrowBody);
            loadOneArrow();
            break;

        case 'a': m_launchSpeed *= 1.02f; break;
        case 's': m_launchSpeed *= 0.98f; break;

        case 'm': m_useWeldJoint = !m_useWeldJoint; break;

        case 'w': g_showArrowGraphic = !g_showArrowGraphic;

        default: Test::Keyboard(key);
        }
    }

    void PostSolve(b2Contact* contact, const b2ContactImpulse* impulse)
    {
        b2Fixture* fixtureA = contact->GetFixtureA();
        b2Fixture* fixtureB = contact->GetFixtureB();

        //fixture with user data is a target, other fixture is arrow or apple
        TargetParameters* targetInfoA = (TargetParameters*)fixtureA->GetUserData();
        TargetParameters* targetInfoB = (TargetParameters*)fixtureB->GetUserData();

        //ignore the apple falling onto the ground
        if ( (targetInfoB && fixtureA->GetShape()->GetType() == b2Shape::e_circle) ||
             (targetInfoA && fixtureB->GetShape()->GetType() == b2Shape::e_circle) )
            return;

        if ( targetInfoA && impulse->normalImpulses[0] > targetInfoA->hardness ) {
            StickyInfo si;
            si.targetBody = fixtureA->GetBody();
            si.arrowBody = fixtureB->GetBody();
            m_collisionsToMakeSticky.push_back(si);
        }
        else if ( targetInfoB && impulse->normalImpulses[0] > targetInfoB->hardness )
        {
            StickyInfo si;
            si.targetBody = fixtureB->GetBody();
            si.arrowBody = fixtureA->GetBody();
            m_collisionsToMakeSticky.push_back(si);
        }
    }

    void Step(Settings* settings)
    {
        //position the loaded arrow
        b2Vec2 startingPosition = m_launcherBody->GetWorldPoint( b2Vec2(3.5f,0) );
        m_loadedArrowBody->SetTransform( startingPosition, m_launcherBody->GetAngle() );

        float dragConstant = 0.1f;

        //apply drag force to arrows
        for (int i = 0; i < m_arrowBodies.size(); i++)
        {
            b2Body* arrowBody = m_arrowBodies[i];

            b2Vec2 flightDirection = arrowBody->GetLinearVelocity();
            float flightSpeed = flightDirection.Normalize();//normalizes and returns length
            b2Vec2 pointingDirection = arrowBody->GetWorldVector( b2Vec2( 1, 0 ) );
            float dot = b2Dot( flightDirection, pointingDirection );

            float dragForceMagnitude = (1 - fabs(dot)) * flightSpeed * flightSpeed * dragConstant * arrowBody->GetMass();

            b2Vec2 arrowTailPosition = arrowBody->GetWorldPoint( b2Vec2( -1.4, 0 ) );
            arrowBody->ApplyForce( dragForceMagnitude * -flightDirection, arrowTailPosition );
        }

        //move the kinetic body target
        b2Vec2 nowKinematicPos = m_kinematicBody->GetPosition();
        b2Vec2 newKinematicPos( 40, 50 + sinf(m_stepCount * 0.01f) * 25 );
        m_kinematicBody->SetLinearVelocity( newKinematicPos - nowKinematicPos );

        //set up drawing flags - needed to maintain custom debug draw
        uint32 flags = 0;
        flags += settings->drawShapes           	* b2Draw::e_shapeBit;
        flags += settings->drawJoints			* b2Draw::e_jointBit;
        flags += settings->drawAABBs			* b2Draw::e_aabbBit;
        flags += settings->drawPairs			* b2Draw::e_pairBit;
        flags += settings->drawCOMs			* b2Draw::e_centerOfMassBit;
        spDebugDraw.SetFlags(flags);

        Test::Step(settings);

        //process arrows that collided this frame
        std::sort( m_collisionsToMakeSticky.begin(), m_collisionsToMakeSticky.end() );
        m_collisionsToMakeSticky.erase( unique( m_collisionsToMakeSticky.begin(), m_collisionsToMakeSticky.end() ), m_collisionsToMakeSticky.end() );
        for (int i = 0; i < m_collisionsToMakeSticky.size(); i++)
        {
            StickyInfo& si = m_collisionsToMakeSticky[i];

            if ( m_useWeldJoint ) {
                //set the joint anchors at the arrow tip - should be good enough
                b2Vec2 worldCoordsAnchorPoint = si.arrowBody->GetWorldPoint( b2Vec2(0.6f, 0) );

                b2WeldJointDef weldJointDef;
                weldJointDef.bodyA = si.targetBody;
                weldJointDef.bodyB = si.arrowBody;
                weldJointDef.localAnchorA = weldJointDef.bodyA->GetLocalPoint( worldCoordsAnchorPoint );
                weldJointDef.localAnchorB = weldJointDef.bodyB->GetLocalPoint( worldCoordsAnchorPoint );
                weldJointDef.referenceAngle = weldJointDef.bodyB->GetAngle() - weldJointDef.bodyA->GetAngle();
                m_world->CreateJoint( &weldJointDef );
            }
            else  {
                //start with standard positions as for normal arrow creation
                b2Vec2 vertices[4];
                vertices[0].Set( -1.4f,     0 );
                vertices[1].Set(     0, -0.1f );
                vertices[2].Set(  0.6f,     0 );
                vertices[3].Set(     0,  0.1f );

                //now multiply by difference between arrow and target transforms
                b2Transform diffTransform = b2MulT( si.targetBody->GetTransform(), si.arrowBody->GetTransform() );
                for (int i = 0; i < 4; i++)
                    vertices[i] = b2Mul(diffTransform, vertices[i]);

                b2PolygonShape polygonShape;
                polygonShape.Set(vertices, 4);

                //create a new fixture in the target body
                b2FixtureDef fixtureDef;
                fixtureDef.shape = &polygonShape;
                fixtureDef.density = 1;
                si.targetBody->CreateFixture( &fixtureDef );

                //discard the original arrow body
                m_world->DestroyBody( si.arrowBody );
            }

        }
        m_collisionsToMakeSticky.clear();

        //show some useful info
        m_debugDraw.DrawString(5, m_textLine, "Use q to fire an arrow");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Use a/s to change the launch velocity");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Use m to toggle stick-in mode");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Use w to toggle arrow draw");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Current launch velocity: %.1f", m_launchSpeed);
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Number of arrows: %d", m_arrowBodies.size());
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Current stick-in mode: %s", m_useWeldJoint?"weld joint":"create new fixture");
        m_textLine += 15;
    }

    static Test* Create()
    {
        return new iforce2d_StickyProjectiles;


    }

    b2Body* m_loadedArrowBody;//keep this out of the vector until fired
    vector<b2Body*> m_arrowBodies;

    b2Body* m_launcherBody;
    float m_launchSpeed;

    TargetParameters m_strawTarget;
    TargetParameters m_woodTarget;
    TargetParameters m_steelTarget;

    vector<StickyInfo> m_collisionsToMakeSticky;

    b2Body* m_kinematicBody;

    bool m_useWeldJoint;//if false, create new fixtures in target body

};

#endif
