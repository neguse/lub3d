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

#ifndef IFORCE2D_TOPDOWN_CAR_H
#define IFORCE2D_TOPDOWN_CAR_H

#include <vector>

#ifndef DEGTORAD
#define DEGTORAD 0.0174532925199432957f
#define RADTODEG 57.295779513082320876f
#endif

enum {
    TDC_LEFT     = 0x1,
    TDC_RIGHT    = 0x2,
    TDC_UP       = 0x4,
    TDC_DOWN     = 0x8
};


class TDTire {
public:
    b2Body* m_body;
    float m_maxForwardSpeed;
    float m_maxBackwardSpeed;
    float m_maxDriveForce;

    TDTire(b2World* world) {
        b2BodyDef bodyDef;
        bodyDef.type = b2_dynamicBody;
        m_body = world->CreateBody(&bodyDef);

        b2PolygonShape polygonShape;
        polygonShape.SetAsBox( 0.5f, 1.25f );
        m_body->CreateFixture(&polygonShape, 1);//shape density
    }

    void setCharacteristics(float maxForwardSpeed, float maxBackwardSpeed, float maxDriveForce) {
        m_maxForwardSpeed = maxForwardSpeed;
        m_maxBackwardSpeed = maxBackwardSpeed;
        m_maxDriveForce = maxDriveForce;
    }

    b2Vec2 getLateralVelocity() {
        b2Vec2 currentRightNormal = m_body->GetWorldVector( b2Vec2(1,0) );
        return b2Dot( currentRightNormal, m_body->GetLinearVelocity() ) * currentRightNormal;
    }

    b2Vec2 getForwardVelocity() {
        b2Vec2 currentForwardNormal = m_body->GetWorldVector( b2Vec2(0,1) );
        return b2Dot( currentForwardNormal, m_body->GetLinearVelocity() ) * currentForwardNormal;
    }

    void updateFriction() {
        //lateral linear velocity
        float maxLateralImpulse = 2.5f;
        b2Vec2 impulse = m_body->GetMass() * -getLateralVelocity();
        if ( impulse.Length() > maxLateralImpulse )
            impulse *= maxLateralImpulse / impulse.Length();
        m_body->ApplyLinearImpulse( impulse, m_body->GetWorldCenter() );

        //angular velocity
        m_body->ApplyAngularImpulse( 0.1f * m_body->GetInertia() * -m_body->GetAngularVelocity() );

        //forward linear velocity
        b2Vec2 currentForwardNormal = getForwardVelocity();
        float currentForwardSpeed = currentForwardNormal.Normalize();
        float dragForceMagnitude = -2 * currentForwardSpeed;
        m_body->ApplyForce( dragForceMagnitude * currentForwardNormal, m_body->GetWorldCenter() );
    }

    void updateDrive(int controlState) {

        //find desired speed
        float desiredSpeed = 0;
        switch ( controlState & (TDC_UP|TDC_DOWN) ) {
            case TDC_UP:   desiredSpeed = m_maxForwardSpeed;  break;
            case TDC_DOWN: desiredSpeed = m_maxBackwardSpeed; break;
            default: return;//do nothing
        }

        //find current speed in forward direction
        b2Vec2 currentForwardNormal = m_body->GetWorldVector( b2Vec2(0,1) );
        float currentSpeed = b2Dot( getForwardVelocity(), currentForwardNormal );

        //apply necessary force
        float force = 0;
        if ( desiredSpeed > currentSpeed )
            force = m_maxDriveForce;
        else if ( desiredSpeed < currentSpeed )
            force = -m_maxDriveForce;
        else
            return;
        m_body->ApplyForce( force * currentForwardNormal, m_body->GetWorldCenter() );
    }

    void updateTurn(int controlState) {
        float desiredTorque = 0;
        switch ( controlState & (TDC_LEFT|TDC_RIGHT) ) {
            case TDC_LEFT:  desiredTorque = 15;  break;
            case TDC_RIGHT: desiredTorque = -15; break;
            default: ;//nothing
        }
        m_body->ApplyTorque( desiredTorque );
    }
};



class iforce2d_TopdownCar : public Test
{
public:
    iforce2d_TopdownCar()
    {
        m_world->SetGravity( b2Vec2(0,0) );

        m_tire = new TDTire(m_world);
        m_tire->setCharacteristics(100, -20, 150);

        m_controlState = 0;
    }

    void Keyboard(unsigned char key)
    {
        switch (key) {
        case 'a' : m_controlState |= TDC_LEFT; break;
        case 'd' : m_controlState |= TDC_RIGHT; break;
        case 'w' : m_controlState |= TDC_UP; break;
        case 's' : m_controlState |= TDC_DOWN; break;
        default: Test::Keyboard(key);
        }
    }

    void KeyboardUp(unsigned char key)
    {
        switch (key) {
        case 'a' : m_controlState &= ~TDC_LEFT; break;
        case 'd' : m_controlState &= ~TDC_RIGHT; break;
        case 'w' : m_controlState &= ~TDC_UP; break;
        case 's' : m_controlState &= ~TDC_DOWN; break;
        default: Test::Keyboard(key);
        }
    }

    void Step(Settings* settings)
    {
        m_tire->updateFriction();
        m_tire->updateDrive(m_controlState);
        m_tire->updateTurn(m_controlState);

        Test::Step(settings);

        //show some useful info
        m_debugDraw.DrawString(5, m_textLine, "Press w/a/s/d to control the car");
        m_textLine += 15;
    }

    static Test* Create()
    {
        return new iforce2d_TopdownCar;
    }

    int m_controlState;
    TDTire* m_tire;

};

#endif
