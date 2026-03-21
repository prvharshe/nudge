import SwiftUI
import SceneKit
import UIKit

// MARK: - TrackSceneView

struct TrackSceneView: UIViewRepresentable {
    let isDark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = context.coordinator.scene
        v.isPlaying = true
        v.loops = true
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        context.coordinator.apply(isDark: isDark, animated: false)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.apply(isDark: isDark, animated: true)
    }
}

// MARK: - Coordinator

extension TrackSceneView {

    final class Coordinator {
        let scene = SCNScene()

        private let sunNode     = SCNNode()
        private let ambientNode = SCNNode()
        private var lampLights  : [SCNNode]     = []
        private var lampBulbs   : [SCNMaterial] = []
        private var groundMat   : SCNMaterial!
        private var pathMat     : SCNMaterial!
        private var canopyMats  : [SCNMaterial] = []
        private var treeNodes   : [SCNNode]     = []   // for sway animation
        private var orbNodes    : [SCNNode]     = []   // firefly orbs (night only)

        // S-curve path through the park (isometric: high +x,+z = near, low -x,-z = far)
        private let pathPoints: [SIMD3<Float>] = [
            [ 3.5, 0.14,  4.5],
            [ 2.5, 0.14,  3.8],
            [ 1.5, 0.14,  3.2],
            [ 0.5, 0.14,  2.5],
            [-0.5, 0.14,  2.0],
            [-1.5, 0.14,  1.2],
            [-1.5, 0.14,  0.0],
            [-0.5, 0.14, -0.8],
            [-1.0, 0.14, -1.8],
            [-2.0, 0.14, -2.8],
            [-3.0, 0.14, -3.8],
        ]

        init() { buildScene() }

        // MARK: - Build

        private func buildScene() {
            setupCamera()
            setupLights()
            addGround()
            addPath()
            addTrees()
            addLamps()
            addNightOrbs()
        }

        // ── Camera ────────────────────────────────────────────────────────────

        private func setupCamera() {
            let cam = SCNCamera()
            cam.usesOrthographicProjection = true
            cam.orthographicScale = 8.5
            cam.zNear = 1
            cam.zFar  = 200
            let node = SCNNode()
            node.camera = cam
            node.position = SCNVector3(10, 11, 10)
            node.look(at: SCNVector3(0, 0, 0),
                      up: SCNVector3(0, 1, 0),
                      localFront: SCNVector3(0, 0, -1))
            scene.rootNode.addChildNode(node)
        }

        // ── Lights ────────────────────────────────────────────────────────────

        private func setupLights() {
            let sun = SCNLight()
            sun.type = .directional
            sun.intensity = 1000
            sun.color = UIColor(hex: "FFF8E0")
            sun.castsShadow = true
            sun.shadowColor = UIColor.black.withAlphaComponent(0.28)
            sun.shadowRadius = 4
            sun.shadowSampleCount = 8
            sun.shadowMode = .deferred
            sunNode.light = sun
            sunNode.eulerAngles = SCNVector3(-Float.pi / 3.5, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sunNode)

            let amb = SCNLight()
            amb.type = .ambient
            amb.intensity = 350
            amb.color = UIColor.white
            ambientNode.light = amb
            scene.rootNode.addChildNode(ambientNode)
        }

        // ── Ground ────────────────────────────────────────────────────────────

        private func addGround() {
            let floor = SCNFloor()
            floor.reflectivity = 0
            groundMat = mat("5D8A3C")
            floor.materials = [groundMat]
            scene.rootNode.addChildNode(SCNNode(geometry: floor))
        }

        // ── Path ─────────────────────────────────────────────────────────────

        private func addPath() {
            pathMat = mat("A0896C")
            for i in 0..<(pathPoints.count - 1) {
                let a = pathPoints[i], b = pathPoints[i + 1]
                let dx = b.x - a.x, dz = b.z - a.z
                let len = sqrt(dx*dx + dz*dz)
                let mx = (a.x + b.x) * 0.5, mz = (a.z + b.z) * 0.5

                let box = SCNBox(width: 0.95, height: 0.14,
                                 length: CGFloat(len) + 0.15, chamferRadius: 0.05)
                box.materials = [pathMat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(mx, 0.07, mz)
                node.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
                scene.rootNode.addChildNode(node)
            }
        }

        // ── Trees ─────────────────────────────────────────────────────────────

        private func addTrees() {
            let positions: [(Float, Float, Float)] = [
                (-5.5, 2.0, 1.15), (-4.5, 4.5, 0.85), (-5.2, 0.0, 1.0), (-4.0, -3.5, 1.2),
                ( 4.0, 3.5, 1.0),  ( 5.3, 1.5, 0.80), ( 4.5,-0.5, 1.1),  ( 4.0,-2.5, 0.9),
                (-2.0, 5.5, 1.0),  ( 0.0, 5.3, 1.3),  ( 2.2, 5.5, 0.85),
                (-0.5,-4.5, 1.1),  ( 1.5,-4.5, 0.80), ( 3.2,-4.0, 1.2),
                ( 5.5,-2.2, 1.0),  (-6.0, 0.5, 0.90), ( 4.0, 4.8, 0.95),
                (-3.5, 2.8, 0.75), ( 2.5,-1.5, 0.70), (-2.5,-1.5, 0.80),
                (-6.5, 3.0, 1.05), ( 6.0, 3.0, 0.85), (-1.0,-5.0, 0.90),
            ]
            for (x, z, s) in positions {
                let t = makeTree(scale: s)
                t.position = SCNVector3(x, 0, z)
                scene.rootNode.addChildNode(t)
                treeNodes.append(t)
            }
            addTreeSway()
        }

        private func makeTree(scale s: Float) -> SCNNode {
            let root = SCNNode()
            let trunkH = CGFloat(0.90 * s)
            let trunk = SCNCylinder(radius: CGFloat(0.11 * s), height: trunkH)
            trunk.materials = [mat("5D4037")]
            let tn = SCNNode(geometry: trunk)
            tn.position = SCNVector3(0, Float(trunkH / 2), 0)
            root.addChildNode(tn)

            for (r, yOff) in [(Float(0.58), Float(0.78)), (0.46, 1.08), (0.30, 1.30)] {
                let sphere = SCNSphere(radius: CGFloat(r * s))
                let cMat = mat("2E7D32")
                sphere.materials = [cMat]
                canopyMats.append(cMat)
                let sn = SCNNode(geometry: sphere)
                sn.position = SCNVector3(0, yOff * s, 0)
                root.addChildNode(sn)
            }
            return root
        }

        // Gentle Z-axis sway — pivot is at the tree base (natural lean)
        private func addTreeSway() {
            for (i, tree) in treeNodes.enumerated() {
                let maxAngle = CGFloat(Float.pi / 180 * (1.2 + Float(i % 3) * 0.4))
                let dur = 1.8 + Double(i % 4) * 0.35
                let leanRight = SCNAction.rotateTo(x: 0, y: 0, z:  maxAngle, duration: dur)
                let leanLeft  = SCNAction.rotateTo(x: 0, y: 0, z: -maxAngle, duration: dur)
                leanRight.timingMode = .easeInEaseOut
                leanLeft.timingMode  = .easeInEaseOut
                let wait = SCNAction.wait(duration: Double(i % 5) * 0.4)
                tree.runAction(.sequence([wait, .repeatForever(.sequence([leanRight, leanLeft]))]))
            }
        }

        // ── Lamps ─────────────────────────────────────────────────────────────

        private func addLamps() {
            let positions: [(Float, Float)] = [
                (-2.5, 4.8), (1.0, 3.5), (2.2, 0.8),
                ( 0.8,-1.5), (-1.5,-2.8), (-3.2,-3.8),
            ]
            for (x, z) in positions {
                let lamp = makeLamp()
                lamp.position = SCNVector3(x, 0, z)
                scene.rootNode.addChildNode(lamp)
            }
        }

        private func makeLamp() -> SCNNode {
            let root = SCNNode()
            let poleMat = SCNMaterial()
            poleMat.diffuse.contents  = UIColor(hex: "546E7A")
            poleMat.specular.contents = UIColor.white.withAlphaComponent(0.2)
            poleMat.lightingModel = .phong

            let shaft = SCNCylinder(radius: 0.055, height: 2.4)
            shaft.materials = [poleMat]
            let shaftNode = SCNNode(geometry: shaft); shaftNode.position = SCNVector3(0, 1.2, 0)
            root.addChildNode(shaftNode)

            let arm = SCNCylinder(radius: 0.035, height: 0.55)
            arm.materials = [poleMat]
            let armNode = SCNNode(geometry: arm)
            armNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            armNode.position = SCNVector3(0.275, 2.42, 0)
            root.addChildNode(armNode)

            let hood = SCNCone(topRadius: 0.07, bottomRadius: 0.22, height: 0.18)
            let hoodMat = SCNMaterial(); hoodMat.diffuse.contents = UIColor(hex: "37474F"); hoodMat.lightingModel = .phong
            hood.materials = [hoodMat]
            let hoodNode = SCNNode(geometry: hood); hoodNode.position = SCNVector3(0.55, 2.48, 0)
            root.addChildNode(hoodNode)

            let bulb = SCNSphere(radius: 0.09)
            let bulbMat = SCNMaterial()
            bulbMat.diffuse.contents  = UIColor(hex: "CCCCCC")
            bulbMat.emission.contents = UIColor.black
            bulbMat.lightingModel = .phong
            bulb.materials = [bulbMat]
            lampBulbs.append(bulbMat)
            let bulbNode = SCNNode(geometry: bulb); bulbNode.position = SCNVector3(0.55, 2.35, 0)
            root.addChildNode(bulbNode)

            let light = SCNLight()
            light.type = .omni; light.intensity = 0
            light.color = UIColor(hex: "FFF3CD")
            light.attenuationStartDistance = 0.5
            light.attenuationEndDistance   = 5.5
            light.attenuationFalloffExponent = 2
            let lightNode = SCNNode(); lightNode.light = light
            lightNode.position = SCNVector3(0.55, 2.35, 0)
            root.addChildNode(lightNode)
            lampLights.append(lightNode)

            return root
        }

        // ── Night orbs (fireflies) ────────────────────────────────────────────

        private func addNightOrbs() {
            // Float near the path at varying heights
            let positions: [(Float, Float, Float)] = [   // x, y, z
                ( 0.0, 0.55, 1.8),
                (-1.0, 0.70, 0.2),
                ( 0.3, 0.45, 2.8),
                (-1.8, 0.60,-1.2),
                (-0.5, 0.80, -0.5),
                ( 0.8, 0.50, 3.5),
            ]
            for (i, (x, y, z)) in positions.enumerated() {
                let orb = SCNSphere(radius: 0.055)
                let orbMat = SCNMaterial()
                orbMat.diffuse.contents  = UIColor(hex: "FFF9E0")
                orbMat.emission.contents = UIColor(hex: "FFF9E0")
                orbMat.lightingModel = .constant
                orb.materials = [orbMat]

                let node = SCNNode(geometry: orb)
                node.position = SCNVector3(x, y, z)
                node.opacity = 0   // hidden by default (day mode)
                scene.rootNode.addChildNode(node)
                orbNodes.append(node)

                // Vertical float
                let dur = 1.4 + Double(i % 3) * 0.45
                let up   = SCNAction.moveBy(x: 0, y: 0.18, z: 0, duration: dur)
                let down = SCNAction.moveBy(x: 0, y: -0.18, z: 0, duration: dur)
                up.timingMode   = .easeInEaseOut
                down.timingMode = .easeInEaseOut
                let phaseWait = SCNAction.wait(duration: Double(i) * 0.5)
                node.runAction(.sequence([phaseWait, .repeatForever(.sequence([up, down]))]))

                // Slow horizontal drift
                let driftDur = 3.5 + Double(i % 4) * 0.6
                let driftA = SCNAction.moveBy(x:  0.25, y: 0, z:  0.15, duration: driftDur)
                let driftB = SCNAction.moveBy(x: -0.25, y: 0, z: -0.15, duration: driftDur)
                driftA.timingMode = .easeInEaseOut
                driftB.timingMode = .easeInEaseOut
                node.runAction(.repeatForever(.sequence([driftA, driftB])))

                // Twinkle (opacity pulse) — runs even when hidden, visible only in night mode
                let twinkleOut = SCNAction.fadeOpacity(to: 0.4, duration: 0.6 + Double(i % 3) * 0.3)
                let twinkleIn  = SCNAction.fadeOpacity(to: 1.0, duration: 0.6 + Double(i % 3) * 0.3)
                node.runAction(.sequence([phaseWait, .repeatForever(.sequence([twinkleOut, twinkleIn]))]))
            }
        }

        // MARK: - Day / Night

        func apply(isDark: Bool, animated: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.85 : 0

            scene.background.contents = isDark
                ? UIColor(hex: "0A1628")
                : UIColor(hex: "8ECAE6")

            sunNode.light?.intensity = isDark ? 0    : 1000
            sunNode.light?.color     = UIColor(hex: isDark ? "1E3A5F" : "FFF8E0")

            ambientNode.light?.intensity = isDark ? 160 : 350
            ambientNode.light?.color     = isDark ? UIColor(hex: "1E3A5F") : .white

            lampLights.forEach { $0.light?.intensity = isDark ? 650 : 0 }
            lampBulbs.forEach { m in
                m.emission.contents = isDark ? UIColor(hex: "FFF3CD") : UIColor.black
                m.diffuse.contents  = isDark ? UIColor(hex: "FFF9C4") : UIColor(hex: "AAAAAA")
            }

            groundMat.diffuse.contents = isDark ? UIColor(hex: "1A3A1A") : UIColor(hex: "5D8A3C")
            pathMat.diffuse.contents   = isDark ? UIColor(hex: "7A6A55") : UIColor(hex: "A0896C")
            canopyMats.forEach {
                $0.diffuse.contents = isDark ? UIColor(hex: "1B4020") : UIColor(hex: "2E7D32")
            }

            // Show firefly orbs only at night
            let orbOpacity: CGFloat = isDark ? 1.0 : 0.0
            orbNodes.forEach { $0.opacity = orbOpacity }

            SCNTransaction.commit()
        }

        // MARK: - Material helper

        private func mat(_ hex: String) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(hex: hex)
            m.lightingModel = .lambert
            return m
        }
    }
}
