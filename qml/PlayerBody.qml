// The MIT License (MIT)
//
// Copyright (c) 2015 Jocelyn Turcotte
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import main 1.0
import Box2DStatic 2.0
import QtMultimedia 5.0
import QtQuick 2.2
import QtQuick.Particles 2.0

LightedImage {
    id: root
    property var model
    property string playerImage

    width: playerDiameterMeters * boxWorld.pixelsPerMeter
    height: playerDiameterMeters * boxWorld.pixelsPerMeter

    sourceImage: playerImage
    normalsImage: "qrc:/images/saucer_normals.png"
    lightSources: lights

    Text {
        x : (parent.width - contentWidth) / 2
        y : (parent.height - contentHeight) / 2
        width: parent.width / 2
        height: parent.height / 2
        color: "#7fffffff"
        fontSizeMode: Text.Fit
        font.pointSize: 72
        font.weight: Font.Bold
        font.family: "Arial"
        text: model ? model.name.slice(0, 2) : ""
    }
    Emitter {
        id: fireEmitter
        property real lightIntensity: 0
        system: flamePainter.system
        width: 25
        height: 25
        enabled: false

        lifeSpan: 160

        velocity: PointDirection { xVariation: width * 2; yVariation: height * 2 }

        size: 24
        sizeVariation: size
        Component.onCompleted: {
            // Add the item itself just to get a sync when it moves
            var jsArray = [fireEmitter, root]
            for (var i in lights.sources)
                jsArray.push(lights.sources[i])
            lights.sources = jsArray
        }
        Component.onDestruction: {
            var jsArray = []
            for (var i in lights.sources) {
                var o = lights.sources[i]
                if (o != fireEmitter && o != root)
                    jsArray.push(o)
            }
            lights.sources = jsArray
        }
    }

    transformOrigin: Item.TopLeft
    property QtObject body: Body {
        target: root
        world: boxWorld

        linearDamping: 1
        angularDamping: 1
        sleepingAllowed: true
        bullet: true // Ensures that the player doesn't jump over bodies within a step
        bodyType: Body.Dynamic
        Circle {
            radius: root.width / 2
            density: 1
            friction: 0.4
            restitution: 1
        }
    }
    Connections {
        target: model
        onTouchMove: {
            function velocityDifferenceVector(toProj, onto) {
                // Find what part of the push to removed in account for the current velocity
                // of the body (like when you can't get any faster on a bicycle unless you
                // start pedaling faster than what the current speed is rotating the traction
                // wheel).
                // There is surely a better formula than this, but here take the projection
                // of the input movement onto the current velocity vector, and remove that part,
                // clamping what we remove between 0 and the length of the velocity vector.
                var unitOnto = onto.normalized()
                var projLength = toProj.dotProduct(unitOnto)
                var effectiveProjLength = Math.max(0, Math.min(projLength, onto.length()))
                return unitOnto.times(effectiveProjLength)
            }
            function rotate(vec, deg)
            {
                var rad = deg * Math.PI / 180
                var x = vec.x * Math.cos(rad) - vec.y * Math.sin(rad)
                var y = vec.x * Math.sin(rad) + vec.y * Math.cos(rad)
                return Qt.vector2d(x, y)
            }
            if (!boxWorld.running)
                return

            // Moving the finger 75px per second will be linearly reduced by a speed of 1m per second.
            var inputPixelPerMeter = 75
            // How much fraction of a second it takes to reach the mps described by the finger.
            // 1/8th of a second will be needed for the ball to reach the finger mps speed
            // (given that we only accelerate using the velocity difference between the controller
            // and the player body).
            var accelFactor = body.getMass() * 8

            var moveTime = time ? time : 16
            var bodyVelMPS = body.linearVelocity
            var moveVecMPS = Qt.vector2d(x, y).times(1000 / moveTime / inputPixelPerMeter)
            var velVecMPS = Qt.vector2d(bodyVelMPS.x, bodyVelMPS.y)
            var inputAdjustmentVec = velocityDifferenceVector(moveVecMPS, velVecMPS)
            var adjustedMove = moveVecMPS.minus(inputAdjustmentVec)

            var appliedForce = adjustedMove.times(accelFactor)
            body.applyForceToCenter(Qt.point(appliedForce.x, appliedForce.y))

            var v = Qt.vector2d(x, y)
            var fireVel = v.normalized().times(-200)
            fireEmitter.velocity.x = fireVel.x
            fireEmitter.velocity.y = fireVel.y
            fireEmitter.burst(v.length())
            fireEmitter.lightIntensity += v.length() * 0.05
            if (fireEmitter.lightIntensity > 2)
                fireEmitter.lightIntensity = 2

            // Move the emitter to the edge of the body
            var p = fireEmitter.parent
            var center = Qt.vector2d(p.width / 2, p.height / 2)
            var vecFromCenter = rotate(v.normalized().times(p.width / 2 - fireEmitter.width), -root.rotation)
            var pos = center.minus(vecFromCenter).minus(Qt.vector2d(fireEmitter.width / 2, fireEmitter.height / 2))
            fireEmitter.x = pos.x
            fireEmitter.y = pos.y
        }
        onTouchStart: { thrusterLowSound.play(); thrusterHighSound.play() }
    }
    SoundEffect {
        id: thrusterLowSound
        muted: !thrusterHighSound.muted || fireEmitter.lightIntensity < 0.1
        loops: SoundEffect.Infinite
        source: "qrc:/sounds/thruster_low.wav"
    }
    SoundEffect {
        id: thrusterHighSound
        muted: fireEmitter.lightIntensity < 0.8
        loops: SoundEffect.Infinite
        source: "qrc:/sounds/thruster_high.wav"
    }
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: if (fireEmitter.lightIntensity > 0.01) fireEmitter.lightIntensity *= 0.5; else fireEmitter.lightIntensity = 0
    }
}
