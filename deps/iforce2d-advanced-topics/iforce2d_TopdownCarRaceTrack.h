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

#ifndef IFORCE2D_TOPDOWN_CAR_RACETRACK_H
#define IFORCE2D_TOPDOWN_CAR_RACETRACK_H

#include <vector>
#include <set>

#include "../Framework/b2dJson.h"

#ifndef DEGTORAD
#define DEGTORAD 0.0174532925199432957f
#define RADTODEG 57.295779513082320876f
#endif

enum {
    TDCR_LEFT     = 0x1,
    TDCR_RIGHT    = 0x2,
    TDCR_UP       = 0x4,
    TDCR_DOWN     = 0x8
};

//types of fixture user data
enum fixtureUserDataTypeR {
    FUDR_GROUND_AREA,
    FUDR_CAR_TIRE,
    FUDR_TRACK_WALL,
    FUDR_BARREL
};

//a class to allow subclassing of different fixture user data
class FixtureUserDataR {
    fixtureUserDataTypeR m_type;
protected:
    FixtureUserDataR(fixtureUserDataTypeR type) : m_type(type) {}
public:
    virtual fixtureUserDataTypeR getType() { return m_type; }
    virtual ~FixtureUserDataR() {}

    bool operator < (const FixtureUserDataR& other) { return true; }
};

//class to allow marking a fixture as a ground area
class GroundAreaFUDR : public FixtureUserDataR {
public:
    float frictionModifier;
    float dragModifier;

    GroundAreaFUDR(float fm, float dm) : FixtureUserDataR(FUDR_GROUND_AREA) {
        frictionModifier = fm;
        dragModifier = dm;
    }
};

//classes to allow marking fixtures as certain things for the game logic to work with.
//In this example the wall and barrel are not used but this would be something you'd need
//  to do if you wanted to play a different sound when the car hits different things.
class CarTireFUDR :      public FixtureUserDataR { public: CarTireFUDR() :     FixtureUserDataR(FUDR_CAR_TIRE) {} };
class TrackWallFUDR :    public FixtureUserDataR { public: TrackWallFUDR() :   FixtureUserDataR(FUDR_TRACK_WALL) {} };
class BarrelFUDR :       public FixtureUserDataR { public: BarrelFUDR() :      FixtureUserDataR(FUDR_BARREL) {} };




class TDRTire {
public:
    b2Body* m_body;
    float m_maxForwardSpeed;
    float m_maxBackwardSpeed;
    float m_maxDriveForce;
    float m_maxLateralImpulse;
    std::set<GroundAreaFUDR*> m_groundAreas;
    float m_currentTraction;
    float m_currentDrag;

    float m_lastDriveImpulse;
    float m_lastLateralFrictionImpulse;

    TDRTire(b2World* world) {
        b2BodyDef bodyDef;
        bodyDef.type = b2_dynamicBody;
        m_body = world->CreateBody(&bodyDef);

        b2PolygonShape polygonShape;
        polygonShape.SetAsBox( 0.5f, 1.25f );
        b2Fixture* fixture = m_body->CreateFixture(&polygonShape, 1);//shape, density
        fixture->SetUserData( new CarTireFUDR() );

        m_body->SetUserData( this );

        m_currentTraction = 1;
        m_currentDrag = 1;
    }

    ~TDRTire() {
        m_body->GetWorld()->DestroyBody(m_body);
    }

    void setCharacteristics(float maxForwardSpeed, float maxBackwardSpeed, float maxDriveForce, float maxLateralImpulse) {
        m_maxForwardSpeed = maxForwardSpeed;
        m_maxBackwardSpeed = maxBackwardSpeed;
        m_maxDriveForce = maxDriveForce;
        m_maxLateralImpulse = maxLateralImpulse;
    }

    void addGroundArea(GroundAreaFUDR* ga) { m_groundAreas.insert(ga); updateTractionAndDrag(); }
    void removeGroundArea(GroundAreaFUDR* ga) { m_groundAreas.erase(ga); updateTractionAndDrag(); }

    void updateTractionAndDrag()
    {
        if ( m_groundAreas.empty() ) {
            m_currentTraction = 1;
            m_currentDrag = 1;
        }
        else {
            //find area with highest traction, same for drag
            m_currentTraction = 0;
            m_currentDrag = 1;//not zero!
            std::set<GroundAreaFUDR*>::iterator it = m_groundAreas.begin();
            while (it != m_groundAreas.end()) {
                GroundAreaFUDR* ga = *it;
                if ( ga->frictionModifier > m_currentTraction )
                    m_currentTraction = ga->frictionModifier;
                if ( ga->dragModifier > m_currentDrag )
                    m_currentDrag = ga->dragModifier;
                ++it;
            }
        }
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
        /*b2Vec2 impulse = m_body->GetMass() * -getLateralVelocity();
        if ( impulse.Length() > m_maxLateralImpulse )
            impulse *= m_maxLateralImpulse / impulse.Length();
        m_body->ApplyLinearImpulse( m_currentTraction * impulse, m_body->GetWorldCenter() );*/

        //angular velocity
        m_body->ApplyAngularImpulse( m_currentTraction * 0.1f * m_body->GetInertia() * -m_body->GetAngularVelocity() );

        //forward linear velocity
        b2Vec2 currentForwardNormal = getForwardVelocity();
        float currentForwardSpeed = currentForwardNormal.Normalize();
        float dragForceMagnitude = -0.25 * currentForwardSpeed;
        dragForceMagnitude *= m_currentDrag;
        m_body->ApplyForce( m_currentTraction * dragForceMagnitude * currentForwardNormal, m_body->GetWorldCenter() );
    }

    void updateDrive(int controlState) {

        //find desired speed
        float desiredSpeed = 0;
        switch ( controlState & (TDCR_UP|TDCR_DOWN) ) {
            case TDCR_UP:   desiredSpeed = m_maxForwardSpeed;  break;
            case TDCR_DOWN: desiredSpeed = m_maxBackwardSpeed; break;
            default: ;//do nothing
        }

        //find current speed in forward direction
        b2Vec2 currentForwardNormal = m_body->GetWorldVector( b2Vec2(0,1) );
        float currentSpeed = b2Dot( getForwardVelocity(), currentForwardNormal );

        //apply necessary force
        float force = 0;
        if ( controlState & (TDCR_UP|TDCR_DOWN) ) {
            if ( desiredSpeed > currentSpeed )
                force = m_maxDriveForce;
            else if ( desiredSpeed < currentSpeed )
                force = -m_maxDriveForce * 0.5f;
        }

        //m_body->ApplyForce( m_currentTraction * force * currentForwardNormal, m_body->GetWorldCenter() );

        float speedFactor = currentSpeed / 120;

        b2Vec2 driveImpulse = (force / 60.0f) * currentForwardNormal;
        if ( driveImpulse.Length() > m_maxLateralImpulse )
            driveImpulse *= m_maxLateralImpulse / driveImpulse.Length();

        b2Vec2 lateralFrictionImpulse = m_body->GetMass() * -getLateralVelocity();
        float lateralImpulseAvailable = m_maxLateralImpulse;
        lateralImpulseAvailable *= 2.0f * speedFactor;
        if ( lateralImpulseAvailable < 0.5f * m_maxLateralImpulse )
            lateralImpulseAvailable = 0.5f * m_maxLateralImpulse;
        /*else if ( lateralImpulseAvailable > m_maxLateralImpulse )
            lateralImpulseAvailable = m_maxLateralImpulse;*/
        if ( lateralFrictionImpulse.Length() > lateralImpulseAvailable )
            lateralFrictionImpulse *= lateralImpulseAvailable / lateralFrictionImpulse.Length();

        m_lastDriveImpulse = driveImpulse.Length();
        m_lastLateralFrictionImpulse = lateralFrictionImpulse.Length();

        b2Vec2 impulse = driveImpulse + lateralFrictionImpulse;
        if ( impulse.Length() > m_maxLateralImpulse )
            impulse *= m_maxLateralImpulse / impulse.Length();
        m_body->ApplyLinearImpulse( m_currentTraction * impulse, m_body->GetWorldCenter() );

        //wheelspin should be max at standstill, and zero at maximum speed
        /*float topSpeed = 120;//estimated from playing around, not critical
        float wsCurve = ( topSpeed - currentSpeed ) / topSpeed;
        wheelspin *= 0.75f * wsCurve;

        float lateralImpulseAvailable = m_maxLateralImpulse;
        lateralImpulseAvailable -= wheelspin;
        if ( lateralImpulseAvailable < 4 )
            lateralImpulseAvailable = 4;
        if ( lateralFrictionImpulse.Length() > lateralImpulseAvailable )
            lateralFrictionImpulse *= lateralImpulseAvailable / lateralFrictionImpulse.Length();
        m_body->ApplyLinearImpulse( m_currentTraction * lateralFrictionImpulse, m_body->GetWorldCenter() );


        m_lastDriveImpulse = impulse.Length();
        m_lastLateralFrictionImpulse = lateralFrictionImpulse.Length();*/

    }

    /*void updateTurn(int controlState) {
        float desiredTorque = 0;
        switch ( controlState & (TDC_LEFT|TDC_RIGHT) ) {
            case TDC_LEFT:  desiredTorque = 15;  break;
            case TDC_RIGHT: desiredTorque = -15; break;
            default: ;//nothing
        }
        m_body->ApplyTorque( desiredTorque );
    }*/
};


class TDRCar {
public:
    b2Body* m_body;
    std::vector<TDRTire*> m_tires;
    b2RevoluteJoint *flJoint, *frJoint;

    TDRCar(b2World* world) {

        //create car body
        b2BodyDef bodyDef;
        bodyDef.type = b2_dynamicBody;
        m_body = world->CreateBody(&bodyDef);
        m_body->SetAngularDamping(5);

        b2Vec2 vertices[8];
        vertices[0].Set( 1.5,   0);
        vertices[1].Set(   3, 2.5);
        vertices[2].Set( 2.8, 5.5);
        vertices[3].Set(   1,  10);
        vertices[4].Set(  -1,  10);
        vertices[5].Set(-2.8, 5.5);
        vertices[6].Set(  -3, 2.5);
        vertices[7].Set(-1.5,   0);
        b2PolygonShape polygonShape;
        polygonShape.Set( vertices, 8 );
        b2Fixture* fixture = m_body->CreateFixture(&polygonShape, 0.1f);//shape, density

        //prepare common joint parameters
        b2RevoluteJointDef jointDef;
        jointDef.bodyA = m_body;
        jointDef.enableLimit = true;
        jointDef.lowerAngle = 0;
        jointDef.upperAngle = 0;
        jointDef.localAnchorB.SetZero();//center of tire

        float maxForwardSpeed = 300;
        float maxBackwardSpeed = -40;/*
        float backTireMaxDriveForce = 400;
        float frontTireMaxDriveForce = 400;
        float backTireMaxLateralImpulse = 8.5;
        float frontTireMaxLateralImpulse = 8.5;*/
        float backTireMaxDriveForce = 950;
        float frontTireMaxDriveForce = 400;
        float backTireMaxLateralImpulse = 9;
        float frontTireMaxLateralImpulse = 9;

        //back left tire
        TDRTire* tire = new TDRTire(world);
        tire->setCharacteristics(maxForwardSpeed, maxBackwardSpeed, backTireMaxDriveForce, backTireMaxLateralImpulse);
        jointDef.bodyB = tire->m_body;
        jointDef.localAnchorA.Set( -3, 0.75f );
        world->CreateJoint( &jointDef );
        m_tires.push_back(tire);

        //back right tire
        tire = new TDRTire(world);
        tire->setCharacteristics(maxForwardSpeed, maxBackwardSpeed, backTireMaxDriveForce, backTireMaxLateralImpulse);
        jointDef.bodyB = tire->m_body;
        jointDef.localAnchorA.Set( 3, 0.75f );
        world->CreateJoint( &jointDef );
        m_tires.push_back(tire);

        //front left tire
        tire = new TDRTire(world);
        tire->setCharacteristics(maxForwardSpeed, maxBackwardSpeed, frontTireMaxDriveForce, frontTireMaxLateralImpulse);
        jointDef.bodyB = tire->m_body;
        jointDef.localAnchorA.Set( -3, 8.5f );
        flJoint = (b2RevoluteJoint*)world->CreateJoint( &jointDef );
        m_tires.push_back(tire);

        //front right tire
        tire = new TDRTire(world);
        tire->setCharacteristics(maxForwardSpeed, maxBackwardSpeed, frontTireMaxDriveForce, frontTireMaxLateralImpulse);
        jointDef.bodyB = tire->m_body;
        jointDef.localAnchorA.Set( 3, 8.5f );
        frJoint = (b2RevoluteJoint*)world->CreateJoint( &jointDef );
        m_tires.push_back(tire);
    }

    ~TDRCar() {
        for (int i = 0; i < m_tires.size(); i++)
            delete m_tires[i];
    }

    void update(int controlState) {
        for (int i = 0; i < m_tires.size(); i++)
            m_tires[i]->updateFriction();
        for (int i = 0; i < m_tires.size(); i++)
            m_tires[i]->updateDrive(controlState);

        //control steering
        float lockAngle = 35 * DEGTORAD;
        float turnSpeedPerSec = 320 * DEGTORAD;//from lock to lock in 0.25 sec
        float turnPerTimeStep = turnSpeedPerSec / 60.0f;
        float desiredAngle = 0;
        switch ( controlState & (TDCR_LEFT|TDCR_RIGHT) ) {
        case TDCR_LEFT:  desiredAngle = lockAngle;  break;
        case TDCR_RIGHT: desiredAngle = -lockAngle; break;
        default: ;//nothing
        }
        float angleNow = flJoint->GetJointAngle();
        float angleToTurn = desiredAngle - angleNow;
        angleToTurn = b2Clamp( angleToTurn, -turnPerTimeStep, turnPerTimeStep );
        float newAngle = angleNow + angleToTurn;
        flJoint->SetLimits( newAngle, newAngle );
        frJoint->SetLimits( newAngle, newAngle );
    }

    b2Vec2 getForwardVelocity() {
        b2Vec2 currentForwardNormal = m_body->GetWorldVector( b2Vec2(0,1) );
        return b2Dot( currentForwardNormal, m_body->GetLinearVelocity() ) * currentForwardNormal;
    }

};




class MyDestructionListenerR :  public b2DestructionListener
{
    void SayGoodbye(b2Fixture* fixture)
    {
        if ( FixtureUserDataR* fud = (FixtureUserDataR*)fixture->GetUserData() )
            delete fud;
    }

    //(unused but must implement all pure virtual functions)
    void SayGoodbye(b2Joint* joint) {}
};






class iforce2d_TopdownCarRaceTrack : public Test
{
public:
    iforce2d_TopdownCarRaceTrack()
    {
        //replace the testbed's default world with the one saved in json file
        {
            b2dJson json;
            b2World* world = json.readFromFile("racetrack.json");
            if ( world ) {
                delete m_world;
                m_world = world;

                m_world->SetContactListener(this);
                m_world->SetDebugDraw(&m_debugDraw);

                b2BodyDef bodyDef;
                m_groundBody = m_world->CreateBody(&bodyDef);
            }

            b2FrictionJointDef frictionJointDef;
            frictionJointDef.localAnchorA.SetZero();
            frictionJointDef.localAnchorB.SetZero();
            frictionJointDef.bodyA = m_groundBody;
            frictionJointDef.maxForce = 400;
            frictionJointDef.maxTorque = 400;
            frictionJointDef.collideConnected = true;

            vector<b2Body*> barrelBodies;
            json.getBodiesByName("barrel", barrelBodies);
            for (int i = 0; i < barrelBodies.size(); i++) {
                b2Body* barrelBody = barrelBodies[i];
                frictionJointDef.bodyB = barrelBody;
                m_world->CreateJoint( &frictionJointDef );
            }

            vector<b2Fixture*> waterFixtures;
            json.getFixturesByName("water", waterFixtures);
            for (int i = 0; i < waterFixtures.size(); i++) {
                b2Fixture* waterFixture = waterFixtures[i];
                waterFixture->SetUserData( new GroundAreaFUDR(1, 30) );
            }
        }

        m_world->SetGravity( b2Vec2(0,0) );
        m_world->SetDestructionListener(&m_destructionListener);

        m_car = new TDRCar(m_world);

        m_controlState = 0;
    }

    ~iforce2d_TopdownCarRaceTrack()
    {
        delete m_car;

        //call DestroyBody for every body to invoke destruction listener to clear fixture user data automatically
        for ( b2Body* b = m_world->GetBodyList(); b ; ) {
            b2Body* nextBody = b->GetNext();
            m_world->DestroyBody( b );
            b = nextBody;
        }
    }

    void Keyboard(unsigned char key)
    {
        switch (key) {
        case 'a' : m_controlState |= TDCR_LEFT; break;
        case 'd' : m_controlState |= TDCR_RIGHT; break;
        case 'w' : m_controlState |= TDCR_UP; break;
        case 's' : m_controlState |= TDCR_DOWN; break;
        default: Test::Keyboard(key);
        }
    }

    void KeyboardUp(unsigned char key)
    {
        switch (key) {
        case 'a' : m_controlState &= ~TDCR_LEFT; break;
        case 'd' : m_controlState &= ~TDCR_RIGHT; break;
        case 'w' : m_controlState &= ~TDCR_UP; break;
        case 's' : m_controlState &= ~TDCR_DOWN; break;
        default: Test::Keyboard(key);
        }
    }

    void handleContact(b2Contact* contact, bool began)
    {
        b2Fixture* a = contact->GetFixtureA();
        b2Fixture* b = contact->GetFixtureB();
        FixtureUserDataR* fudA = (FixtureUserDataR*)a->GetUserData();
        FixtureUserDataR* fudB = (FixtureUserDataR*)b->GetUserData();

        if ( !fudA || !fudB )
            return;

        if ( fudA->getType() == FUDR_CAR_TIRE && fudB->getType() == FUDR_GROUND_AREA )
            tire_vs_groundArea(a, b, began);
        else if ( fudA->getType() == FUDR_GROUND_AREA && fudB->getType() == FUDR_CAR_TIRE )
            tire_vs_groundArea(b, a, began);

        //could have checks here to play sounds or give damage to car when hitting
        //barrels or wall etc.
    }

    void BeginContact(b2Contact* contact) { handleContact(contact, true); }
    void EndContact(b2Contact* contact) { handleContact(contact, false); }

    void tire_vs_groundArea(b2Fixture* tireFixture, b2Fixture* groundAreaFixture, bool began)
    {
        TDRTire* tire = (TDRTire*)tireFixture->GetBody()->GetUserData();
        GroundAreaFUDR* gaFud = (GroundAreaFUDR*)groundAreaFixture->GetUserData();
        if ( began )
            tire->addGroundArea( gaFud );
        else
            tire->removeGroundArea( gaFud );
    }

    void Step(Settings* settings)
    {
        m_car->update(m_controlState);

        Test::Step(settings);

        //adjust view center as car moves
        b2Vec2 oldViewCenter = settings->viewCenter;
        b2Vec2 posOfCarVerySoon = m_car->m_body->GetPosition() + 0.25f * m_car->m_body->GetLinearVelocity();
        settings->viewCenter = 0.9f * oldViewCenter + 0.1f * posOfCarVerySoon;

        //show some useful info
        m_debugDraw.DrawString(5, m_textLine, "Press w/a/s/d to control the car");
        m_textLine += 15;

        m_debugDraw.DrawString(5, m_textLine, "Speed: %.2f", m_car->getForwardVelocity().Length());
        m_textLine += 15;

        for (int i = 0; i < 4; i++) {
            TDRTire* tire = m_car->m_tires[i];
            //m_debugDraw.DrawString(5, m_textLine, "Drive impulse: %.2f, lateral impulse: %.2f", tire->m_lastDriveImpulse, tire->m_lastLateralFrictionImpulse);
            //m_textLine += 15;
        }

        //m_debugDraw.DrawString(5, m_textLine, "Tire traction: %.2f", m_tire->m_currentTraction);
        //m_textLine += 15;
    }

    static Test* Create()
    {
        return new iforce2d_TopdownCarRaceTrack;
    }

    int m_controlState;
    MyDestructionListenerR m_destructionListener;

    TDRCar* m_car;

};

#endif
