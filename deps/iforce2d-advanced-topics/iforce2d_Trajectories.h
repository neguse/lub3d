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

#ifndef IFORCE2D_TRAJECTORIES_H
#define IFORCE2D_TRAJECTORIES_H

#ifndef DEGTORAD
#define DEGTORAD 0.0174532925199432957f
#define RADTODEG 57.295779513082320876f
#endif

// This callback finds the closest hit, optionally ignoring one particular body
class TrajectoryRayCastClosestCallback : public b2RayCastCallback
{
public:
    TrajectoryRayCastClosestCallback(b2Body* ignoreBody) : m_hit(false), m_ignoreBody(ignoreBody) {}

    float32 ReportFixture(b2Fixture* fixture, const b2Vec2& point, const b2Vec2& normal, float32 fraction)
    {
        if ( fixture->GetBody() == m_ignoreBody )
            return -1;

        m_hit = true;
        m_point = point;
        m_normal = normal;
        return fraction;
    }

    b2Body* m_ignoreBody;
    bool m_hit;
    b2Vec2 m_point;
    b2Vec2 m_normal;
};

#define BALL_SIZE 0.25f

class iforce2d_Trajectories : public Test
{
public:
    iforce2d_Trajectories()
    {
        //add four walls to the ground body
        b2FixtureDef myFixtureDef;
        b2PolygonShape polygonShape;
        myFixtureDef.shape = &polygonShape;
        polygonShape.SetAsBox( 20, 1, b2Vec2(0, 0), 0);//ground
        m_groundBody->CreateFixture(&myFixtureDef);
        polygonShape.SetAsBox( 20, 1, b2Vec2(0, 40), 0);//ceiling
        m_groundBody->CreateFixture(&myFixtureDef);
        polygonShape.SetAsBox( 1, 20, b2Vec2(-20, 20), 0);//left wall
        m_groundBody->CreateFixture(&myFixtureDef);
        polygonShape.SetAsBox( 1, 20, b2Vec2(20, 20), 0);//right wall
        m_groundBody->CreateFixture(&myFixtureDef);

        //small ledges for target practice
        myFixtureDef.friction = 0.95f;
        polygonShape.SetAsBox( 1.5f, 0.25f, b2Vec2(3, 35), 0);
        m_groundBody->CreateFixture(&myFixtureDef);
        polygonShape.SetAsBox( 1.5f, 0.25f, b2Vec2(13, 30), 0);
        m_groundBody->CreateFixture(&myFixtureDef);

        //another ledge which we can move with the mouse
        b2BodyDef kinematicBody;
        kinematicBody.type = b2_kinematicBody;
        kinematicBody.position.Set(11, 22);
        m_targetBody = m_world->CreateBody(&kinematicBody);
        float w = BALL_SIZE;
        float h = BALL_SIZE * 0.5f;
        b2Vec2 verts[3];
        verts[0].Set(  0, -2*w);
        verts[1].Set(  w,    0);
        verts[2].Set(  0,   -w);
        polygonShape.Set( verts, 3 );
        m_targetBody->CreateFixture(&myFixtureDef);
        verts[0].Set(  0, -2*w);
        verts[2].Set(  0,   -w);
        verts[1].Set( -w,    0);
        polygonShape.Set( verts, 3 );
        m_targetBody->CreateFixture(&myFixtureDef);

        //create dynamic circle body
        b2BodyDef myBodyDef;
        myBodyDef.type = b2_dynamicBody;
        myBodyDef.position.Set(-15, 5);
        m_launcherBody = m_world->CreateBody(&myBodyDef);
        b2CircleShape circleShape;
        circleShape.m_radius = 2;
        myFixtureDef.shape = &circleShape;
        myFixtureDef.density = 1;
        b2Fixture* circleFixture = m_launcherBody->CreateFixture(&myFixtureDef);

        //pin the circle in place
        b2RevoluteJointDef revoluteJointDef;
        revoluteJointDef.bodyA = m_groundBody;
        revoluteJointDef.bodyB = m_launcherBody;
        revoluteJointDef.localAnchorA.Set(-15,5);
        revoluteJointDef.localAnchorB.Set(0,0);
        revoluteJointDef.enableMotor = true;
        revoluteJointDef.maxMotorTorque = 250;
        revoluteJointDef.motorSpeed = 0;
        m_world->CreateJoint( &revoluteJointDef );


        //create dynamic box body to fire
        myBodyDef.position.Set(0,-5);//will be positioned later
        m_littleBox = m_world->CreateBody(&myBodyDef);
        myFixtureDef.shape = &polygonShape;
        polygonShape.SetAsBox( 0.5f, 0.5f );
        m_littleBox->CreateFixture(&myFixtureDef);

        //ball for computer 'player' to fire
        m_littleBox2 = m_world->CreateBody(&myBodyDef);
        myFixtureDef.shape = &circleShape;
        circleShape.m_radius = BALL_SIZE;
        circleShape.m_p.SetZero();
        m_littleBox2->CreateFixture(&myFixtureDef);

        m_firing = false;
        m_littleBox->SetGravityScale(0);
        m_launchSpeed = 10;

        m_firing2 = false;
        m_littleBox2->SetGravityScale(0);

        m_mouseWorld = b2Vec2(11,22);//sometimes is not set

    }

    //this just returns the current top edge of the golf-tee thingy
    b2Vec2 getComputerTargetPosition()
    {
        return m_targetBody->GetPosition() + b2Vec2(0, BALL_SIZE + 0.01f );
    }

    //basic trajectory 'point at timestep n' formula
    b2Vec2 getTrajectoryPoint( b2Vec2& startingPosition, b2Vec2& startingVelocity, float n /*time steps*/ )
    {
        float t = 1 / 60.0f;
        b2Vec2 stepVelocity = t * startingVelocity; // m/s
        b2Vec2 stepGravity = t * t * m_world->GetGravity(); // m/s/s

        return startingPosition + n * stepVelocity + 0.5f * (n*n+n) * stepGravity;
    }

    //find out how many timesteps it will take for projectile to reach maximum height
    float getTimestepsToTop( b2Vec2& startingVelocity )
    {
        float t = 1 / 60.0f;
        b2Vec2 stepVelocity = t * startingVelocity; // m/s
        b2Vec2 stepGravity = t * t * m_world->GetGravity(); // m/s/s

        float n = -stepVelocity.y / stepGravity.y - 1;

        return n;
    }

    //find out the maximum height for this parabola
    float getMaxHeight( b2Vec2& startingPosition, b2Vec2& startingVelocity )
    {
        if ( startingVelocity.y < 0 )
            return startingPosition.y;

        float t = 1 / 60.0f;
        b2Vec2 stepVelocity = t * startingVelocity; // m/s
        b2Vec2 stepGravity = t * t * m_world->GetGravity(); // m/s/s

        float n = -stepVelocity.y / stepGravity.y - 1;

        return startingPosition.y + n * stepVelocity.y + 0.5f * (n*n+n) * stepGravity.y;
    }

    //find the initial velocity necessary to reach a specified maximum height
    float calculateVerticalVelocityForHeight( float desiredHeight )
    {
        if ( desiredHeight <= 0 )
            return 0;

        float t = 1 / 60.0f;
        b2Vec2 stepGravity = t * t * m_world->GetGravity(); // m/s/s

        //quadratic equation setup
        float a = 0.5f / stepGravity.y;
        float b = 0.5f;
        float c = desiredHeight;

        float quadraticSolution1 = ( -b - b2Sqrt( b*b - 4*a*c ) ) / (2*a);
        float quadraticSolution2 = ( -b + b2Sqrt( b*b - 4*a*c ) ) / (2*a);

        float v = quadraticSolution1;
        if ( v < 0 )
            v = quadraticSolution2;

        return v * 60.0f;
    }

    //calculate how the computer should launch the ball with the current target location
    b2Vec2 getComputerLaunchVelocity() {
        b2Vec2 targetLocation = getComputerTargetPosition();
        float verticalVelocity = calculateVerticalVelocityForHeight( targetLocation.y - 5 );//computer projectile starts at y = 5
        b2Vec2 startingVelocity(0,verticalVelocity);//only interested in vertical here
        float timestepsToTop = getTimestepsToTop( startingVelocity );
        float targetEdgePos = m_targetBody->GetPosition().x;
        if ( targetEdgePos > 15 )
            targetEdgePos -= BALL_SIZE;
        else
            targetEdgePos += BALL_SIZE;
        float distanceToTargetEdge = targetEdgePos - 15;
        float horizontalVelocity = distanceToTargetEdge / timestepsToTop * 60.0f;
        return b2Vec2( horizontalVelocity, verticalVelocity );
    }

    void Keyboard(unsigned char key)
    {
        switch (key) {
        case 'q':
            m_littleBox->SetAwake(true);
            m_littleBox->SetGravityScale(1);
            m_littleBox->SetAngularVelocity(0);
            m_littleBox->SetTransform( m_launcherBody->GetWorldPoint( b2Vec2(3,0) ), m_launcherBody->GetAngle() );
            m_littleBox->SetLinearVelocity( m_launcherBody->GetWorldVector( b2Vec2(m_launchSpeed,0) ) );
            m_firing = true;
            break;
        case 'w':
            m_littleBox->SetGravityScale(0);
            m_littleBox->SetAngularVelocity(0);
            m_firing = false;
            break;
        case 'a': m_launchSpeed *= 1.02f; break;
        case 's': m_launchSpeed *= 0.98f; break;

        case 'd':
        {
            m_littleBox2->SetAwake(true);
            m_littleBox2->SetGravityScale(1);
            m_littleBox2->SetAngularVelocity(0);
            b2Vec2 launchVel = getComputerLaunchVelocity();
            b2Vec2 computerStartingPosition = b2Vec2(15,5);
            m_littleBox2->SetTransform( computerStartingPosition, 0 );
            m_littleBox2->SetLinearVelocity( launchVel );
            m_firing2 = true;
        }
            break;
        case 'f':
            m_littleBox2->SetGravityScale(0);
            m_littleBox2->SetAngularVelocity(0);
            m_firing2 = false;
            break;

        case 'm' :
            m_targetBody->SetTransform( m_mouseWorld, 0 ); //m_mouseWorld is from Test class
            break;

        default: Test::Keyboard(key);
        }
    }

    void KeyboardUp(unsigned char key)
    {
        switch (key) {
        default: Test::Keyboard(key);
        }
    }

    void Step(Settings* settings)
    {
        b2Vec2 startingPosition = m_launcherBody->GetWorldPoint( b2Vec2(3,0) );
        b2Vec2 startingVelocity =  m_launcherBody->GetWorldVector( b2Vec2(m_launchSpeed,0) );

        if ( !m_firing )
            m_littleBox->SetTransform( startingPosition, m_launcherBody->GetAngle() );

        TrajectoryRayCastClosestCallback raycastCallback(m_littleBox);//this raycast will ignore the little box

        //draw predicted trajectory
        glColor3f(1,1,0);
        glBegin(GL_LINES);
        b2Vec2 lastTP = startingPosition;
        for (int i = 0; i < 300; i++) {//5 seconds, should be long enough to hit something
            b2Vec2 trajectoryPosition = getTrajectoryPoint( startingPosition, startingVelocity, i );

            if ( i > 0 ) {
                m_world->RayCast(&raycastCallback, lastTP, trajectoryPosition);
                if ( raycastCallback.m_hit ) {
                    glVertex2f (raycastCallback.m_point.x, raycastCallback.m_point.y );
                    break;
                }
            }

            glVertex2f (trajectoryPosition.x, trajectoryPosition.y );
            lastTP = trajectoryPosition;
        }
        glEnd();

        glEnable(GL_POINT_SMOOTH);
        glPointSize(5);

        //draw raycast intersect location
        if ( raycastCallback.m_hit ) {
            glColor3f(0,1,1);
            glBegin(GL_POINTS);
            glVertex2f(raycastCallback.m_point.x, raycastCallback.m_point.y);
            glEnd();
        }

        //draw dot in center of fired box
        glColor3f(0,1,0);
        glBegin(GL_POINTS);
        b2Vec2 littleBoxPos = m_littleBox->GetPosition();
        glVertex2f (littleBoxPos.x, littleBoxPos.y );
        glEnd();

        //draw maximum height line
        float maxHeight = getMaxHeight( startingPosition, startingVelocity );
        glEnable(GL_BLEND);
        glColor4f(1,1,1,0.5f);
        glBegin(GL_LINES);
        glVertex2f (-20, maxHeight );
        glVertex2f ( 20, maxHeight );
        glEnd();


        //draw line to indicate velocity computer player will fire at
        b2Vec2 launchVel = getComputerLaunchVelocity();
        b2Vec2 computerStartingPosition = b2Vec2(15,5);
        b2Vec2 displayVelEndPoint = computerStartingPosition + 0.1f * launchVel;
        glBegin(GL_LINES);
        glColor3f(1,0,0);
        glVertex2f( computerStartingPosition.x, computerStartingPosition.y );
        glColor3f(0,1,0);
        glVertex2f( displayVelEndPoint.x, displayVelEndPoint.y );
        glEnd();

        if ( !m_firing2 )
            m_littleBox2->SetTransform( computerStartingPosition, 0 );


        Test::Step(settings);


        m_debugDraw.DrawString(5, m_textLine, "Rotate the circle on the left to change launch direction");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Use a/s to change the launch speed");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Use q/w to launch and reset the projectile");
        m_textLine += 15;
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Use d/f to launch and reset the computer controlled projectile");
        m_textLine += 15;
        m_debugDraw.DrawString(5, m_textLine, "Hold down m and use the left mouse button to move the computer's target");
        m_textLine += 15;
    }

    static Test* Create()
    {
        return new iforce2d_Trajectories;
    }

    b2Body* m_launcherBody;
    b2Body* m_littleBox;
    b2Body* m_littleBox2;
    b2Body* m_targetBody;
    bool m_firing;
    bool m_firing2;
    float m_launchSpeed;
};

#endif
