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

#ifndef IFORCE2D_HOVERCAR_SUSPENSION_H
#define IFORCE2D_HOVERCAR_SUSPENSION_H

#ifndef DEGTORAD
#define DEGTORAD 0.0174532925199432957f
#define RADTODEG 57.295779513082320876f
#endif

#include <vector>

//typical closest hit callback
class HovercarRayCastClosestCallback : public b2RayCastCallback
{
public:
    HovercarRayCastClosestCallback()
    {
        m_hit = false;
    }

    float32 ReportFixture(b2Fixture* fixture, const b2Vec2& point, const b2Vec2& normal, float32 fraction)
    {
        m_hit = true;
        m_point = point;
        return fraction;
    }

    bool m_hit;
    b2Vec2 m_point;
};

enum {
    CS_LEFT     = 0x1,
    CS_RIGHT    = 0x2,
    CS_FLY      = 0x4
};

//random number between 0 and 1
float rnd_1()
{
    return rand() / (float)RAND_MAX;
}

class iforce2d_HovercarSuspension : public Test
{
public:
    iforce2d_HovercarSuspension()
    {
        /*{//boring ground
            b2EdgeShape edgeShape;
            edgeShape.Set( b2Vec2(-20,0), b2Vec2(20,0) );

            b2BodyDef bodyDef;
            m_world->CreateBody(&bodyDef)->CreateFixture(&edgeShape, 0);
        }*/

        {//interesting ground
            b2BodyDef bodyDef;
            b2Body* groundBody = m_world->CreateBody(&bodyDef);

            float height = 2;
            b2EdgeShape edgeShape;
            b2Vec2 lastPoint( -60, rnd_1() * height );
            for (int i = -61; i < 60; i++) {
                b2Vec2 thisPoint(i,rnd_1() * height);
                edgeShape.Set( lastPoint, thisPoint );
                lastPoint = thisPoint;
                groundBody->CreateFixture(&edgeShape, 0);
            }
        }

        {//hovercar
            b2BodyDef bodyDef;
            bodyDef.type = b2_dynamicBody;
            bodyDef.fixedRotation = true;
            bodyDef.position.Set(0,10);
            m_hovercarBody = m_world->CreateBody(&bodyDef);

            b2PolygonShape polygonShape;
            polygonShape.SetAsBox(2,0.5f);//4x1 box
            b2FixtureDef fixtureDef;
            fixtureDef.shape = &polygonShape;
            fixtureDef.density = 1;
            fixtureDef.friction = 0.8f;

            m_hovercarBody->CreateFixture(&fixtureDef);
        }

        {//little boxes
            b2BodyDef bodyDef;
            bodyDef.type = b2_dynamicBody;
            bodyDef.position.Set(0,15);

            b2PolygonShape polygonShape;
            polygonShape.SetAsBox(0.5f,0.5f);//1x1 box
            b2FixtureDef fixtureDef;
            fixtureDef.shape = &polygonShape;
            fixtureDef.density = 1;
            fixtureDef.friction = 0.8f;

            for (int i = 0; i < 10; i++)
                m_world->CreateBody(&bodyDef)->CreateFixture(&fixtureDef);
        }

        m_controlState = 0;
    }

    void Keyboard(unsigned char key)
    {
        switch (key) {
        case 'a' : m_controlState |= CS_LEFT; break;
        case 'd' : m_controlState |= CS_RIGHT; break;
        case 'w' : m_controlState |= CS_FLY; break;

        default: Test::Keyboard(key);
        }
    }

    void KeyboardUp(unsigned char key)
    {
        switch (key) {
        case 'a' : m_controlState &= ~CS_LEFT; break;
        case 'd' : m_controlState &= ~CS_RIGHT; break;
        case 'w' : m_controlState &= ~CS_FLY; break;

        default: Test::Keyboard(key);
        }
    }

    void Step(Settings* settings)
    {
        float targetHeight = 3;
        float springConstant = 50;
        float distanceAboveGround = FLT_MAX;

        //you could loop this section and find the average distance, min distance etc for more than one ray
        {
            //make the ray at least as long as the target distance
            b2Vec2 startOfRay = m_hovercarBody->GetWorldPoint( b2Vec2(0,-0.5f) );
            b2Vec2 endOfRay = m_hovercarBody->GetWorldPoint( b2Vec2(0,-5) );

            //draw the ray
            glColor3f(1,1,1);
            glBegin(GL_LINES);
            glVertex2f(startOfRay.x, startOfRay.y);
            glVertex2f(endOfRay.x, endOfRay.y);
            glEnd();

            HovercarRayCastClosestCallback callback;
            m_world->RayCast(&callback, startOfRay, endOfRay);

            if ( callback.m_hit )
                distanceAboveGround = (startOfRay - callback.m_point).Length();
        }

        //dont do anything if too far above ground
        if ( distanceAboveGround < targetHeight ) {

            //replace distanceAboveGround with the 'look ahead' distance
            //this will look ahead 0.25 seconds - longer gives more 'damping'
            distanceAboveGround += 0.25f * m_hovercarBody->GetLinearVelocity().y;

            float distanceAwayFromTargetHeight = targetHeight - distanceAboveGround;
            m_hovercarBody->ApplyForce( b2Vec2(0,springConstant*distanceAwayFromTargetHeight), m_hovercarBody->GetWorldCenter() );

            //negate gravity
            m_hovercarBody->ApplyForce( m_hovercarBody->GetMass() * -m_world->GetGravity(), m_hovercarBody->GetWorldCenter() );
        }

        //user controlled movement
        {
            float maxLateralVelocity = 10;
            float maxVerticalVelocity = 10;
            float lateralForce = 50;
            float flyForce = 100;

            b2Vec2 controlForce(0,0);

            int lateral = m_controlState & (CS_LEFT|CS_RIGHT);
            if ( lateral == CS_LEFT && m_hovercarBody->GetLinearVelocity().x > -maxLateralVelocity )
                controlForce.x = -lateralForce;
            else if ( lateral == CS_RIGHT && m_hovercarBody->GetLinearVelocity().x < maxLateralVelocity )
                controlForce.x = lateralForce;

            if ( m_controlState & CS_FLY && m_hovercarBody->GetLinearVelocity().y < maxVerticalVelocity )
                controlForce.y = flyForce;

            m_hovercarBody->ApplyForce( controlForce, m_hovercarBody->GetWorldCenter() );
        }

        Test::Step(settings);

        //show some useful info
        m_debugDraw.DrawString(5, m_textLine, "Press a/d to move left/right, w to fly upwards");
        m_textLine += 15;
        if ( distanceAboveGround == FLT_MAX )
            m_debugDraw.DrawString(5, m_textLine, "Distance above ground: (out of range)" );
        else
            m_debugDraw.DrawString(5, m_textLine, "Distance above ground: %.3f", distanceAboveGround);
        m_textLine += 15;

    }

    static Test* Create()
    {
        return new iforce2d_HovercarSuspension;
    }

    b2Body* m_hovercarBody;
    int m_controlState;

};

#endif
