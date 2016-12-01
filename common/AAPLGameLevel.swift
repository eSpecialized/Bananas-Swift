//
//  AAPLGameLevel.swift
//  Bananas
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/21.
//  Copyright © 2015 Apple Inc. All rights reserved.
//
/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:

 This class manages most of the game logic, including setting up the scene and keeping score.

 */

import SceneKit

import SpriteKit

@objc(AAPLGameLevel)
class AAPLGameLevel: NSObject, AAPLGameUIState {
    
    var playerCharacter: AAPLPlayerCharacter?
    var monkeyCharacter: AAPLPlayerCharacter?
    var camera: SCNNode?
    var bananas: Set<SCNNode> = []
    var largeBananas: Set<SCNNode> = []
    var coconuts: [SCNNode] = []
    var hitByLavaReset: Bool = false
    
    var timeAlongPath: SCNVectorFloat = 0.0
    
    /* GameUIState protocol */
    fileprivate(set) var score: Int = 0
    fileprivate(set) var coinsCollected: Int = 0
    fileprivate(set) var bananasCollected: Int = 0
    fileprivate(set) var secondsRemaining: TimeInterval = 0.0
    var scoreLabelLocation: CGPoint = CGPoint()
    
    //typedef enum {
    //	AAPLShadowReceiverCategory = 2,
    //} AAPLCategoryBitMasks;
    
    let BANANA_SCALE_LARGE: SCNVectorFloat = (0.5 * 10.0/4.0)
    let BANANA_SCALE: SCNVectorFloat = 0.5
    
    fileprivate var _lightOffsetFromCharacter: SCNVector3 = SCNVector3()
    fileprivate var _screenSpaceplayerPosition: SCNVector3 = SCNVector3()
    fileprivate var _worldSpaceLabelScorePosition: SCNVector3 = SCNVector3()
    
    fileprivate var rootNode: SCNNode?
    fileprivate var sunLight: SCNNode?
    fileprivate var pathPositions: [SCNVector3] = []
    fileprivate var bananaCollectable: SCNNode?
    fileprivate var largeBananaCollectable: SCNNode?
    fileprivate var monkeyProtoObject: AAPLSkinnedCharacter?
    fileprivate var coconutProtoObject: SCNNode?
    fileprivate var palmTreeProtoObject: SCNNode?
    fileprivate var monkeys: [AAPLSkinnedCharacter] = []
    
    var highEnd: Bool {
        //todo: return YES on OSX, iPad air, iphone 5s - NO otherwie
        return true
    }
    
    /*! Helper Method for creating a large banana
    Create model, Add particle system, Add persistent SKAction, Add / Setup collision
    */
    fileprivate func createLargeBanana() -> SCNNode {
        if self.largeBananaCollectable == nil {
            let bananaPath = AAPLGameSimulation.pathForArtResource("level/banana.dae")
            let node = AAPLGameSimulation.loadNodeWithName("banana",
                fromSceneNamed: bananaPath)!
            
            node.scale = SCNVector3Make(BANANA_SCALE_LARGE, BANANA_SCALE_LARGE, BANANA_SCALE_LARGE)
            
            let sphereGeometry = SCNSphere(radius: 100)
            let physicsShape = SCNPhysicsShape(geometry: sphereGeometry, options: nil)
            node.physicsBody = SCNPhysicsBody(type: .kinematic, shape: physicsShape)
            
            // Only collide with player and ground
            node.physicsBody!.collisionBitMask = GameCollisionCategoryPlayer | GameCollisionCategoryGround
            if #available(iOS 9.0, OSX 10.11, *) {
                node.physicsBody!.contactTestBitMask = node.physicsBody!.collisionBitMask
            }
            
            // Declare self in the coin category
            node.physicsBody!.categoryBitMask = GameCollisionCategoryCoin
            
            // Rotate forever.
            let rotateCoin = SCNAction.rotateBy(x: 0, y: 8, z: 0, duration: 2.0)
            let repeatAction = SCNAction.repeatForever(rotateCoin)
            
            node.rotation = SCNVector4Make(0, 1, 0, SCNVectorFloat(M_PI_2))
            node.runAction(repeatAction)
            
            self.largeBananaCollectable = node
        }
        
        let node = self.largeBananaCollectable!.clone()
        
        let newSystem = AAPLGameSimulation.loadParticleSystemWithName("sparkle")
        node.addParticleSystem(newSystem)
        
        return node
    }
    
    /*! Helper Method for creating a small banana
    */
    func createBanana() -> SCNNode {
        //Create model
        if self.bananaCollectable == nil {
            self.bananaCollectable = AAPLGameSimulation.loadNodeWithName("banana", fromSceneNamed: AAPLGameSimulation.pathForArtResource("level/banana.dae"))
            
            self.bananaCollectable!.scale = SCNVector3Make(BANANA_SCALE, BANANA_SCALE, BANANA_SCALE)
            
            let sphereGeometry = SCNSphere(radius: 40)
            let physicsShape = SCNPhysicsShape(geometry: sphereGeometry, options: nil)
            
            self.bananaCollectable!.physicsBody = SCNPhysicsBody(type: .kinematic, shape: physicsShape)
            
            // Only collide with player and ground
            self.bananaCollectable!.physicsBody!.collisionBitMask = GameCollisionCategoryPlayer | GameCollisionCategoryGround
            if #available(iOS 9.0, OSX 10.11, *) {
                self.bananaCollectable!.physicsBody!.contactTestBitMask = self.bananaCollectable!.physicsBody!.collisionBitMask
            }
            // Declare self in the banana category
            self.bananaCollectable!.physicsBody!.categoryBitMask = GameCollisionCategoryBanana
            
            // Rotate and Hover forever.
            self.bananaCollectable!.rotation = SCNVector4Make(0.5, 1, 0.5, -SCNVectorFloat(M_PI_4))
            let idleHoverGroupAction = SCNAction.group([self.bananaIdleAction, self.hoverAction])
            let repeatForeverAction = SCNAction.repeatForever(idleHoverGroupAction)
            self.bananaCollectable!.runAction(repeatForeverAction)
        }
        
        return self.bananaCollectable!.clone()
    }
    
    fileprivate func setupPathColliders() {
        // Collect all the nodes that start with path_ under the dummy_front object.
        // Set those objects as Physics category ground and create a static concave mesh collider.
        // The simulation will use these as the ground to walk on.
        let front = self.rootNode?.childNode(withName: "dummy_front", recursively: true)
        front?.enumerateChildNodes{child, stop in
            if child.name?.hasPrefix("path_") ?? false {
                let path = child.childNodes.first; //the geometry is attached to the first child node of the node named path_*
                
                path?.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: path!.geometry!, options: [SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.concavePolyhedron]))
                path?.physicsBody!.categoryBitMask = GameCollisionCategoryGround
            }
        }
    }
    
    fileprivate func collectSortedPathNodes() -> [SCNNode] {
        // Gather all the children under the dummy_master
        // Sort left to right, in the world.
        let pathNodes = self.rootNode?.childNode(withName: "dummy_master", recursively: true)
        
        let sortedNodes = pathNodes?.childNodes.sorted {dummyA, dummyB in
            
            return dummyA.position.x < dummyB.position.x
        }
        return sortedNodes ?? []
    }
    
    fileprivate func convertPathNodesIntoPathPositions() {
        // Walk the path, sampling every little bit, creating a path to follow.
        // We use this path to move along left to right and right to left.
        let sortedNodes = self.collectSortedPathNodes()
        
        self.pathPositions = []
        self.pathPositions.append(SCNVector3Make(0, 0, 0))
        
        for d in sortedNodes {
            if !(d.name?.hasPrefix("dummy_path_") ?? false) {
                continue
            }
            self.pathPositions.append(d.position)
        }
        self.pathPositions.append(SCNVector3Make(0, 0, 0))
    }
    
    fileprivate func resamplePathPositions() {
        // Calc the phatom end control point.
        var controlPointA = self.pathPositions[self.pathPositions.count - 2]
        var controlPointB = self.pathPositions[self.pathPositions.count - 3]
        var controlPoint: SCNVector3 = SCNVector3()
        
        controlPoint.x = controlPointA.x + (controlPointA.x - controlPointB.x)
        controlPoint.y = controlPointA.y + (controlPointA.y - controlPointB.y)
        controlPoint.z = controlPointA.z + (controlPointA.z - controlPointB.z)
        
        self.pathPositions[self.pathPositions.count - 1] = controlPoint
        
        // Calc the phatom begin control point.
        controlPointA = self.pathPositions[1]
        controlPointB = self.pathPositions[2]
        
        controlPoint.x = controlPointA.x + (controlPointA.x - controlPointB.x)
        controlPoint.y = controlPointA.y + (controlPointA.y - controlPointB.y)
        controlPoint.z = controlPointA.z + (controlPointA.z - controlPointB.z)
        self.pathPositions[0] = controlPoint
        
        var newPath: [SCNVector3] = []
        var lastPosition: SCNVector3 = SCNVector3()
        let minDistanceBetweenPoints: Float = 10.0
        let steps = 10000
        for i in 0..<steps {
            let t = SCNVectorFloat(i) / SCNVectorFloat(steps)
            let currentPostion = self.locationAlongPath(t)
            if i == 0 {
                newPath.append(currentPostion)
                lastPosition = currentPostion
            } else {
                let dist = GLKVector3Distance(SCNVector3ToGLKVector3(currentPostion), SCNVector3ToGLKVector3(lastPosition))
                if dist > minDistanceBetweenPoints {
                    newPath.append(currentPostion)
                    lastPosition = currentPostion
                }
            }
        }
        
        // Last Step. Return the path position array for our pathing system to query.
        self.pathPositions = newPath
    }
    
    fileprivate func calculatePathPositions() {
        
        self.setupPathColliders()
        
        self.convertPathNodesIntoPathPositions()
        
        self.resamplePathPositions()
    }
    
    /*! Given a relative percent along the path, return back the world location vector.
    */
    func locationAlongPath(_ percent: SCNVectorFloat) -> SCNVector3 {
        if self.pathPositions.count <= 3 {
            return SCNVector3Make(0, 0, 0)
        }
        
        let numSections = self.pathPositions.count - 3
        var dist = Float(percent) * Float(numSections)
        //print(dist, percent, numSections)
        
        let currentPointIndex = min(Int(floor(max(dist, 0))), numSections - 1)
        //print(dist, floor(dist), Int(floor(dist)), numSections, numSections - 1)
        dist -= Float(currentPointIndex)
        let a = SCNVector3ToGLKVector3(self.pathPositions[currentPointIndex])
        let b = SCNVector3ToGLKVector3(self.pathPositions[currentPointIndex + 1])
        let c = SCNVector3ToGLKVector3(self.pathPositions[currentPointIndex + 2])
        let d = SCNVector3ToGLKVector3(self.pathPositions[currentPointIndex + 3])
        
        var location: SCNVector3 = SCNVector3()
        
        func CatmullRomValue(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ dist: Float) -> SCNVectorFloat {
            let tmp1 = (-a + 3.0 * b - 3.0 * c + d)
            let tmp2 = (2.0 * a - 5.0 * b + 4.0 * c - d)
            let tmp3 = ((-a + c) * dist)
            let dist3 = (dist * dist * dist)
            let dist2 = (dist * dist)
            let tmp4 = ((tmp1 * dist3) +
                (tmp2 * dist2) +
                tmp3 +
                (2.0 * b))
            return SCNVectorFloat(tmp4 * 0.5)
        }
        
        location.x = CatmullRomValue(a.x, b.x, c.x, d.x, dist)
        location.y = CatmullRomValue(a.y, b.y, c.y, d.y, dist)
        location.z = CatmullRomValue(a.z, b.z, c.z, d.z, dist)
        
        return location
    }
    
    /*! Direction player facing given the current walking direction.
    */
    fileprivate func getDirectionFromPosition(_ currentPosition: SCNVector3) -> SCNVector4 {
        
        let target = SCNVector3ToGLKVector3(self.locationAlongPath(self.timeAlongPath - 0.05))
        
        let position = SCNVector3ToGLKVector3(currentPosition)
        let lookat = GLKMatrix4MakeLookAt(position.x, position.y, position.z, target.x, target.y, target.z, 0, 1, 0)
        let q = GLKQuaternionMakeWithMatrix4(lookat)
        
        var angle = SCNVectorFloat(GLKQuaternionAngle(q))
        if self.playerCharacter?.walkDirection == .left {
            angle -= SCNVectorFloat(M_PI)
        }
        return SCNVector4Make(0, 1, 0, angle)
    }
    
    /* Helper method for getting main player's direction
    */
    fileprivate func getPlayerDirectionFromCurrentPosition() -> SCNVector4 {
        return getDirectionFromPosition(self.playerCharacter!.position)
    }
    
    // Helper Method for loading the Swinging Torch
    //
    // Load the dae from disk
    // Attach to origin
    fileprivate func createSwingingTorch() {
        
        let torchSwing = AAPLGameSimulation.loadNodeWithName("dummy_master", fromSceneNamed: AAPLGameSimulation.pathForArtResource("level/torch.dae"))!
        self.rootNode?.addChildNode(torchSwing)
    }
    
    // createLavaAnimation
    //
    // Find the lava nodes in the scene.
    // Add a concave collider to each lava mesh
    // UV animate the lava texture in the vertex shader.
    fileprivate func createLavaAnimation() {
        let lavaNodes = self.rootNode?.childNodes {child, stop in
            child.name?.hasPrefix("lava_0") ?? false
            } ?? []
        
        for lava in lavaNodes {
            let childrenWithGeometry = lava.childNodes {child, stop in
                if child.geometry != nil {
                    stop.pointee = true
                    return true
                }
                
                return false
            }
            
            if let lavaGeometry = childrenWithGeometry.first {
                
                lavaGeometry.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: lavaGeometry.geometry!, options: [SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.concavePolyhedron]))
                lavaGeometry.physicsBody!.categoryBitMask = GameCollisionCategoryLava
                lavaGeometry.categoryBitMask = NodeCategoryLava
                
                let shaderCode =
                "uniform float speed;\n" +
                    "#pragma body\n" +
                "_geometry.texcoords[0] += vec2(sin(_geometry.position.z*0.1 + u_time * 0.1) * 0.1, -1.0* 0.05 * u_time);\n"
                lavaGeometry.geometry!.shaderModifiers = [SCNShaderModifierEntryPoint.geometry : shaderCode]
            }
        }
    }
    
    /*! Create an action that rotates back and forth.
    */
    fileprivate lazy var bananaIdleAction: SCNAction = {
        let rotateAction = SCNAction.rotateBy(x: 0, y: CGFloat(M_PI_2), z: 0, duration: 1.0)
        rotateAction.timingMode = .easeInEaseOut
        let reversed = rotateAction.reversed()
        return SCNAction.sequence([rotateAction, reversed])
    }()
    
    /*! Create an action that hovers up and down slightly.
    */
    fileprivate lazy var hoverAction: SCNAction = {
        let floatAction = SCNAction.moveBy(x: 0, y: 10.0, z: 0, duration: 1.0)
        let floatAction2 = floatAction.reversed()
        floatAction.timingMode = .easeInEaseOut
        floatAction2.timingMode = .easeInEaseOut
        return SCNAction.sequence([floatAction, floatAction2])
    }()
    
    /*! Create an action that pulses the opacity of a node.
    */
    func pulseAction() -> SCNAction {
        let duration: TimeInterval = 8.0 / 6.0
        let pulseAction = SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.fadeOpacity(to: 0.3, duration: duration),
                SCNAction.fadeOpacity(to: 0.5, duration: duration),
                SCNAction.fadeOpacity(to: 1.0, duration: duration),
                SCNAction.fadeOpacity(to: 0.7, duration: duration),
                SCNAction.fadeOpacity(to: 0.4, duration: duration),
                SCNAction.fadeOpacity(to: 0.8, duration: duration)]))
        return pulseAction
    }
    
    /* Create a simple point light
    */
    fileprivate func torchLight() -> SCNLight {
        let light = SCNLight()
        light.type = SCNLight.LightType.omni
        light.color = SKColor.orange
        light.attenuationStartDistance = 350
        light.attenuationEndDistance = 400
        light.attenuationFalloffExponent = 1
        return light
    }
    
    /*! Create a torch node that has a particle effect and point light attached.
    */
    fileprivate func createTorchNode() -> SCNNode {
        struct s {
            static var template: SCNNode?
        }
        
        if s.template == nil {
            s.template = SCNNode()
            
            let geometry = SCNBox(width: 20, height: 100, length: 20, chamferRadius: 10)
            geometry.firstMaterial!.diffuse.contents = SKColor.brown
            s.template!.geometry = geometry
            
            let particleEmitter = SCNNode()
            particleEmitter.position = SCNVector3Make(0, 50, 0)
            
            //let fire = SCNParticleSystem(named: "torch.scnp",
            //inDirectory: "art.scnassets/level/effects")!
            let fire = AAPLGameSimulation.loadParticleSystemWithName("torch") //###
            particleEmitter.addParticleSystem(fire)
            
            particleEmitter.light = self.torchLight()
            
            s.template!.addChildNode(particleEmitter)
        }
        
        return s.template!.clone()
    }
    
    // CreateLevel
    //
    // Load the level dae from disk
    // Setup and construct the level. ( Should really be done offline in an editor ).
    func createLevel() -> SCNNode? {
        
        self.rootNode = SCNNode()
        
        // load level dae and add all root children to the scene.
        #if os(OSX)
            let options = [SCNSceneSource.LoadingOption.convertToYUp: true]
        #else
            let options: [String: AnyObject] = [:]
        #endif
        let scene = SCNScene(named: "level.dae", inDirectory: AAPLGameSimulation.pathForArtResource("level/"), options: options)
        for node in scene?.rootNode.childNodes ?? [] {
            self.rootNode?.addChildNode(node)
        }
        
        // retrieve the main camera
        self.camera = self.rootNode?.childNode(withName: "camera_game", recursively: true)
        
        // create our path that the player character will follow.
        self.calculatePathPositions()
        
        //-- Sun/Moon light
        self.sunLight = self.rootNode?.childNode(withName: "FDirect001", recursively: true)
        self.sunLight?.eulerAngles = SCNVector3Make(7.1 * SCNVectorFloat(M_PI_4), SCNVectorFloat(M_PI_4), 0)
        self.sunLight?.light?.shadowSampleCount = 1; //to match iOS while testing: to be removed from the sample code
        _lightOffsetFromCharacter = SCNVector3Make(1500, 2000, 1000)
        
        //workaround directional light deserialization issue
        self.sunLight?.light?.zNear = 100
        self.sunLight?.light?.zFar = 5000
        self.sunLight?.light?.orthographicScale = 1000
        
        if !self.highEnd {
            //use blob shadows on low end devices
            self.sunLight?.light?.shadowMode = SCNShadowMode.modulated
            self.sunLight?.light?.categoryBitMask = 0x2
            self.sunLight?.light?.orthographicScale = 60
            self.sunLight?.eulerAngles = SCNVector3Make(SCNVectorFloat(M_PI_2), 0, 0)
            _lightOffsetFromCharacter = SCNVector3Make(0, 2000, 0)
            
            self.sunLight?.light?.gobo?.contents = "art.scnassets/techniques/blobShadow.jpg"
            self.sunLight?.light?.gobo?.intensity = 0.5
            
            let middle = self.rootNode?.childNode(withName: "dummy_front", recursively: true)
            middle?.enumerateChildNodes {child, stop in
                child.categoryBitMask = 0x2
            }
        }
        
        //-- Torches
        let  torchesPos: [SCNVectorFloat] = [0, -1, 0.092467, -1, -1, 0.5, 0.7920, 0.953830]
        
        for pos in torchesPos {
            if pos < 0.0 {continue}
            var location = self.locationAlongPath(pos)
            location.y += 50
            location.z += 150
            
            let node = self.createTorchNode()
            
            node.position = location
            self.rootNode?.addChildNode(node)
        }
        
        // After load, we add nodes that are dynamic / animated / or otherwise not static.
        self.createLavaAnimation()
        self.createSwingingTorch()
        self.animateDynamicNodes()
        
        // Create our player character
        let characterRoot = AAPLGameSimulation.loadNodeWithName(nil, fromSceneNamed: "art.scnassets/characters/explorer/explorer_skinned.dae")!
        self.playerCharacter = AAPLPlayerCharacter(node: characterRoot)
        self.timeAlongPath = 0
        self.playerCharacter!.position = self.locationAlongPath(self.timeAlongPath)
        self.playerCharacter!.rotation = self.getPlayerDirectionFromCurrentPosition()
        self.rootNode?.addChildNode(self.playerCharacter!)
        
        // Optimize lighting and shadows
        // only the charadcter should cast shadows
        self.rootNode?.enumerateChildNodes {child, stop in
            child.castsShadow = false
        }
        self.playerCharacter?.enumerateChildNodes {child, stop in
            child.castsShadow = true
        }
        
        // Add some monkeys to the scene.
        self.addMonkeyAtPosition(SCNVector3Make(0, -30, -400), andRotation: 0)
        self.addMonkeyAtPosition(SCNVector3Make(3211, 146, -400), andRotation: CGFloat(-M_PI_4))
        self.addMonkeyAtPosition(SCNVector3Make(5200, 330, 600), andRotation: 0)
        
        //- Volcano
        var oldVolcano = self.rootNode?.childNode(withName: "volcano", recursively: true)
        let volcanoDaeName = AAPLGameSimulation.pathForArtResource("level/volcano_effects.dae")
        let newVolcano = AAPLGameSimulation.loadNodeWithName("dummy_master",
            fromSceneNamed: volcanoDaeName)!
        oldVolcano?.addChildNode(newVolcano)
        oldVolcano?.geometry = nil
        oldVolcano = newVolcano.childNode(withName: "volcano", recursively: true)
        oldVolcano = oldVolcano?.childNodes.first
        
        //-- Animate our dynamic volcano node.
        let shaderCode =
        "uniform float speed;\n" +
            "_geometry.color = vec4(a_color.r, a_color.r, a_color.r, a_color.r);\n" +
        "_geometry.texcoords[0] += (vec2(0.0, 1.0) * 0.05 * u_time);\n"
        
        let fragmentShaderCode =
        "#pragma transparent\n"
        
        //dim background
        let back = self.rootNode?.childNode(withName: "dumy_rear", recursively: true)
        back?.enumerateChildNodes {child, stop in
            child.castsShadow = false
            
            for material in child.geometry?.materials ?? [] {
                material.lightingModel = SCNMaterial.LightingModel.constant
                material.multiply.contents = SKColor(white: 0.3, alpha: 1.0)
                material.multiply.intensity = 1
            }
        }
        
        //remove lighting from middle plane
        do {
            let back = self.rootNode?.childNode(withName: "dummy_middle", recursively: true)
            back?.enumerateChildNodes {child, stop in
                for material in child.geometry?.materials ?? [] {
                    material.lightingModel = SCNMaterial.LightingModel.constant
                }
            }
        }
        
        newVolcano.enumerateChildNodes {child, stop in
            if child !== oldVolcano && child.geometry != nil {
                child.geometry!.firstMaterial?.lightingModel = SCNMaterial.LightingModel.constant
                child.geometry!.firstMaterial?.multiply.contents = SKColor.white
                child.geometry!.shaderModifiers = [SCNShaderModifierEntryPoint.geometry: shaderCode,
                    SCNShaderModifierEntryPoint.fragment: fragmentShaderCode]
            }
        }
        
        
        if !self.highEnd {
            self.rootNode?.enumerateChildNodes {child, stop in
                for m in child.geometry?.materials ?? [] {
                    m.lightingModel = SCNMaterial.LightingModel.constant
                }
            }
            
            self.playerCharacter?.enumerateChildNodes {child, stop in
                for material in child.geometry?.materials ?? [] {
                    material.lightingModel = SCNMaterial.LightingModel.lambert
                }
            }
        }
        
        self.coconuts = []
        return self.rootNode
    }
    
    /*! Given a world position and rotation, load the monkey dae and place it into the world.
    */
    fileprivate func addMonkeyAtPosition(_ worldPos: SCNVector3, andRotation rotation: CGFloat) {
        
        let palmTree = self.createMonkeyPalmTree()
        palmTree.position = worldPos
        palmTree.rotation = SCNVector4Make(0, 1, 0, SCNVectorFloat(rotation))
        self.rootNode?.addChildNode(palmTree)
        
        if let monkey = palmTree.childNode(withName: "monkey", recursively: true) as? AAPLSkinnedCharacter {
            self.monkeys.append(monkey)
        }
    }
    
    /*! Load the palm tree that the monkey is attached to.
    */
    fileprivate func createMonkeyPalmTree() -> SCNNode {
        struct s {
            static var palmTreeProtoObject: SCNNode? = nil
        }
        
        if s.palmTreeProtoObject == nil {
            let palmTreeDae = AAPLGameSimulation.pathForArtResource("characters/monkey/monkey_palm_tree.dae")
            s.palmTreeProtoObject = AAPLGameSimulation.loadNodeWithName("PalmTree",
                fromSceneNamed: palmTreeDae)
        }
        
        let monkeyNode = AAPLGameSimulation.loadNodeWithName(nil, fromSceneNamed: "art.scnassets/characters/monkey/monkey_skinned.dae")!
        
        let monkey = AAPLMonkeyCharacter(node: monkeyNode)
        monkey.createAnimations()
        
        let palmTree = s.palmTreeProtoObject!.clone()
        palmTree.addChildNode(monkey)
        
        return palmTree
    }
    
    fileprivate func animateDynamicNodes() {
        
        var dynamicNodesWithVertColorAnimation: [SCNNode] = []
        
        self.rootNode?.enumerateChildNodes {child, stop in
            let range = child.parent?.name?.range(of: "vine")
            if child.geometry?.getGeometrySources(for: SCNGeometrySource.Semantic.color) == nil {
                //###
            } else if range != nil {
                dynamicNodesWithVertColorAnimation.append(child)
            }
        }
        
        //-- Animate our dynamic node.
        let shaderCode =
        "uniform float timeOffset;\n" +
            "#pragma body\n" +
            "float speed = 20.05;\n" +
        "_geometry.position.xyz += (speed * sin(u_time + timeOffset) * _geometry.color.rgb);\n"
        
        for dynamicNode in dynamicNodesWithVertColorAnimation {
            dynamicNode.geometry!.shaderModifiers = [SCNShaderModifierEntryPoint.geometry : shaderCode]
            let explodeAnimation = CABasicAnimation(keyPath: "timeOffset")
            explodeAnimation.duration = 2.0
            explodeAnimation.repeatCount = FLT_MAX
            explodeAnimation.autoreverses = true
            explodeAnimation.toValue = AAPLRandomPercent() as Double
            explodeAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            dynamicNode.geometry!.addAnimation(explodeAnimation, forKey: "sway")
        }
    }
    
    /*! Reset the game simulation for the start of the game or restart after you have completed the level.
    */
    func resetLevel() {
        score = 0
        secondsRemaining = 120
        coinsCollected = 0
        bananasCollected = 0
        
        self.timeAlongPath = 0
        self.playerCharacter?.position = self.locationAlongPath(self.timeAlongPath)
        self.playerCharacter?.rotation = self.getPlayerDirectionFromCurrentPosition()
        self.hitByLavaReset = false
        
        // Remove dynamic objects from the level.
        SCNTransaction.begin()
        
        for b in self.coconuts {
            b.removeFromParentNode()
        }
        
        for b in self.bananas {
            b.removeFromParentNode()
        }
        
        for largeBanana in self.largeBananas {
            largeBanana.removeFromParentNode()
        }
        SCNTransaction.commit()
        
        // Add dynamic objects to the level, like bananas and large bananas
        self.bananas = []
        self.coconuts = []
        
        for i in 0..<10 {
            let banana = self.createBanana()
            self.rootNode?.addChildNode(banana)
            var location = self.locationAlongPath(SCNVectorFloat(i + 1) / 20.0 - 0.01)
            location.y += 50
            banana.position = location
            
            self.bananas.insert(banana)
        }
        
        self.largeBananas = []
        
        for _ in 0..<6 {
            let largeBanana = self.createLargeBanana()
            self.rootNode?.addChildNode(largeBanana)
            var location = self.locationAlongPath(AAPLRandomPercent())
            location.y += 50
            largeBanana.position = location
            self.largeBananas.insert(largeBanana)
        }
        
        AAPLGameSimulation.sim.playMusic("music.caf")
        AAPLGameSimulation.sim.playMusic("night.caf")
    }
    
    /*! Change the game state to the postgame.
    */
    fileprivate func doGameOver() {
        self.playerCharacter?.inRunAnimation = false
        AAPLGameSimulation.sim.gameState = .postGame
    }
    
    func collideWithLava() {
        if self.hitByLavaReset {
            return
        }
        
        self.playerCharacter?.inRunAnimation = false
        
        AAPLGameSimulation.sim.playSound("ack.caf")
        
        // Blink for a second
        let blinkOffAction = SCNAction.fadeOut(duration: 0.15)
        let blinkOnAction = SCNAction.fadeIn(duration: 0.15)
        let cycle = SCNAction.sequence([blinkOffAction, blinkOnAction])
        let repeatCycle = SCNAction.repeat(cycle, count: 7)
        
        self.hitByLavaReset = true
        
        self.playerCharacter?.runAction(repeatCycle) {
            self.timeAlongPath = 0
            self.playerCharacter!.position = self.locationAlongPath(self.timeAlongPath)
            self.playerCharacter!.rotation = self.getPlayerDirectionFromCurrentPosition()
            self.hitByLavaReset = false
        }
    }
    
    fileprivate func moveCharacterAlongPathWith(_ deltaTime: TimeInterval, currentState: AAPLGameState) {
        if let playerCharacter = self.playerCharacter, playerCharacter.running {
            if currentState == .inGame {
                var walkSpeed = playerCharacter.walkSpeed
                if self.playerCharacter!.jumping {
                    walkSpeed += playerCharacter.jumpBoost
                }
                
                self.timeAlongPath += SCNVectorFloat(CGFloat(deltaTime) * walkSpeed * (playerCharacter.walkDirection == .right ? 1 : -1))
                
                // limit how far the player can go in left and right directions.
                if self.timeAlongPath < 0.0 {
                    self.timeAlongPath = 0.0
                } else if self.timeAlongPath > 1.0 {
                    self.timeAlongPath = 1.0
                }
                
                let newPosition = self.locationAlongPath(self.timeAlongPath)
                playerCharacter.position = SCNVector3Make(newPosition.x, playerCharacter.position.y, newPosition.z)
                if self.timeAlongPath >= 1.0 {
                    self.doGameOver()
                }
            } else {
                playerCharacter.inRunAnimation = false
            }
        }
    }
    
    fileprivate func updateSunLightPosition() {
        var lightPos = _lightOffsetFromCharacter
        let charPos = self.playerCharacter?.position ?? SCNVector3()
        lightPos.x += charPos.x
        lightPos.y += charPos.y
        lightPos.z += charPos.z
        self.sunLight?.position = lightPos
    }
    
    /*! Main game logic
    */
    func update(_ deltaTime: TimeInterval, withRenderer aRenderer: SCNSceneRenderer) {
        
        // Based on gamestate:
        // ingame: Move the character if running.
        // ingame: prevent movement of the character past our level bounds.
        // ingame: perform logic for the player character.
        // any: move the directional light with any player movement.
        // ingame: update the coconuts kinematically.
        // ingame: perform logic for each monkey.
        // ingame: because our camera could have moved, update the transforms needs to fly
        //         collected bananas from the player (world space) to score (screen space)
        //
        
        let appDelegate = AAPLAppDelegate.sharedAppDelegate()
        let currentState = AAPLGameSimulation.sim.gameState
        
        // Move character along path if walking.
        self.moveCharacterAlongPathWith(deltaTime, currentState: currentState)
        
        // Based on the time along path, rotation the character to face the correct direction.
        self.playerCharacter?.rotation = self.getPlayerDirectionFromCurrentPosition()
        if currentState == .inGame {
            self.playerCharacter?.update(deltaTime)
        }
        
        // Move the light
        self.updateSunLightPosition()
        
        if currentState == .preGame ||
            currentState == .postGame ||
            currentState == .paused {
                return
        }
        
        for monkey in self.monkeys {
            monkey.update(deltaTime)
        }
        
        // Update timer and check for Game Over.
        secondsRemaining -= TimeInterval(deltaTime)
        if secondsRemaining < 0.0 {
            self.doGameOver()
        }
        
        // update the player's SP position.
        let playerPosition = AAPLMatrix4GetPosition(self.playerCharacter?.worldTransform ?? SCNMatrix4())
        _screenSpaceplayerPosition = appDelegate.scnView.projectPoint(playerPosition)
        
        // Update the SP position of the score label
        var pt = self.scoreLabelLocation
        #if os(iOS)
            // Unflip coordinate system on iOS.
            pt.y = appDelegate.scnView.frame.size.height - pt.y
        #endif
        _worldSpaceLabelScorePosition = appDelegate.scnView.unprojectPoint(SCNVector3Make(SCNVectorFloat(pt.x), SCNVectorFloat(pt.y), _screenSpaceplayerPosition.z))
    }
    
    func collectBanana(_ banana: SCNNode) {
        // Flyoff the banana to the screen space position score label.
        // Don't increment score until the banana hits the score label.
        
        // ignore collisions
        banana.physicsBody = nil
        bananasCollected += 1
        
        let variance = 60
        let randomY = SCNVectorFloat((Int(arc4random()) % variance) - (variance / 2))
        let apexY = ((_worldSpaceLabelScorePosition.y * 0.8)) + randomY
        _worldSpaceLabelScorePosition.z = banana.position.z
        let apex = SCNVector3Make(banana.position.x + 10 + SCNVectorFloat((Int(arc4random()) % variance) - (variance / 2)), apexY, banana.position.z)
        
        let startFlyOff = SCNAction.move(to: apex, duration: 0.25)
        startFlyOff.timingMode = .easeOut
        
        let duration: TimeInterval = 0.25
        let endFlyOff = SCNAction.customAction(duration: duration) {node, elapsedTime in
            
            let t = SCNVectorFloat(elapsedTime) / SCNVectorFloat(duration)
            let v = SCNVector3(
                x: apex.x + ((self._worldSpaceLabelScorePosition.x - apex.x) * t),
                y: apex.y + ((self._worldSpaceLabelScorePosition.y - apex.y) * t),
                z: apex.z + ((self._worldSpaceLabelScorePosition.z - apex.z) * t))
            node.position = v
        }
        
        endFlyOff.timingMode = .easeInEaseOut
        let flyoffSequence = SCNAction.sequence([startFlyOff, endFlyOff])
        
        banana.runAction(flyoffSequence) {
            self.bananas.remove(banana)
            banana.removeFromParentNode()
            // Add to score.
            self.score += 1
            AAPLGameSimulation.sim.playSound("deposit.caf")
            if self.bananas.isEmpty {
                // Game Over
                self.doGameOver()
            }
        }
    }
    
    func collectLargeBanana(_ largeBanana: SCNNode) {
        // When the player hits a large banana, explode it into smaller bananas.
        // We explode into a predefined pattern: square, diamond, letterA, letterB
        
        // ignore collisions
        largeBanana.physicsBody = nil
        coinsCollected += 1
        
        self.largeBananas.remove(largeBanana)
        largeBanana.removeAllParticleSystems()
        largeBanana.removeFromParentNode()
        
        // Add to score.
        score+=100
        let square: [Int] = [
            1, 1, 1, 1, 1,
            1, 1, 1, 1, 1,
            1, 1, 1, 1, 1,
            1, 1, 1, 1, 1,
            1, 1, 1, 1, 1]
        let diamond: [Int] = [
            0, 0, 1, 0, 0,
            0, 1, 1, 1, 0,
            1, 1, 1, 1, 1,
            0, 1, 1, 1, 0,
            0, 0, 1, 0, 0]
        let letterA: [Int] = [
            1, 0, 0, 1, 0,
            1, 0, 0, 1, 0,
            1, 1, 1, 1, 0,
            1, 0, 0, 1, 0,
            0, 1, 1, 0, 0]
        
        let letterB: [Int] = [
            1, 1, 0, 0, 0,
            1, 0, 1, 0, 0,
            1, 1, 0, 0, 0,
            1, 0, 1, 0, 0,
            1, 1, 0, 0, 0]
        let choices: [[Int]] = [square, diamond, letterA, letterB]
        
        let vertSpacing: SCNVectorFloat = 40
        let spacing: SCNVectorFloat = 0.0075
        let choice = choices[Int(arc4random()) % choices.count]
        for y in 0..<5 {
            for x in 0..<5 {
                let place = choice[(y * 5) + x]
                if place != 1 {
                    continue
                }
                
                let banana = self.createBanana()
                
                self.rootNode?.addChildNode(banana)
                banana.position = largeBanana.position
                banana.physicsBody?.categoryBitMask = GameCollisionCategoryNoCollide
                banana.physicsBody?.collisionBitMask = GameCollisionCategoryGround
                if #available(iOS 9.0, OSX 10.11, *) {
                    banana.physicsBody!.contactTestBitMask = banana.physicsBody!.collisionBitMask
                }
                
                var endPoint = self.locationAlongPath(self.timeAlongPath + (spacing * SCNVectorFloat(x + 1)))
                endPoint.y += (vertSpacing * SCNVectorFloat(y + 1));
                
                let flyoff = SCNAction.move(to: endPoint, duration: AAPLRandomPercent() * 0.25)
                flyoff.timingMode = .easeInEaseOut
                
                // Prevent collision until the banana gets to the final resting spot.
                banana.runAction(flyoff) {
                    banana.physicsBody?.categoryBitMask = GameCollisionCategoryBanana
                    banana.physicsBody?.collisionBitMask = GameCollisionCategoryGround | GameCollisionCategoryPlayer
                    if #available(iOS 9.0, OSX 10.11, *) {
                        banana.physicsBody!.contactTestBitMask = banana.physicsBody!.collisionBitMask
                    }
                    AAPLGameSimulation.sim.playSound("deposit.caf")
                }
                self.bananas.insert(banana)
            }
        }
    }
    
    func collideWithCoconut(_ coconut: SCNNode, point contactPoint: SCNVector3) {
        
        // No more collisions. Let it bounce away and fade out.
        coconut.physicsBody?.collisionBitMask = 0
        if #available(iOS 9.0, OSX 10.11, *) {
            coconut.physicsBody!.contactTestBitMask = coconut.physicsBody!.collisionBitMask
        }
        coconut.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 1.0),
            SCNAction.wait(duration: 1.0),
            SCNAction.removeFromParentNode()])) {
                
                self.coconuts = self.coconuts.filter{$0 !== coconut}
        }
        
        // Decrement score
        var amountToDrop = self.score / 10
        if amountToDrop < 1 {
            amountToDrop = 1
        }
        if amountToDrop > 10 {
        }
        if amountToDrop > score {
            amountToDrop = score
        }
        score -= amountToDrop
        
        // Throw bananas
        let spacing: SCNVectorFloat = 40
        for x in 0..<amountToDrop {
            let banana = self.createBanana()
            
            self.rootNode?.addChildNode(banana)
            banana.position = contactPoint
            banana.physicsBody?.categoryBitMask = GameCollisionCategoryNoCollide
            banana.physicsBody?.collisionBitMask = GameCollisionCategoryGround
            if #available(iOS 9.0, OSX 10.11, *) {
                banana.physicsBody!.contactTestBitMask = banana.physicsBody!.collisionBitMask
            }
            var endPoint = SCNVector3Make(0, 0, 0)
            endPoint.x -= (spacing * SCNVectorFloat(x)) + spacing
            
            let flyoff = SCNAction.move(by: endPoint, duration: AAPLRandomPercent() * 0.750)
            flyoff.timingMode = .easeInEaseOut
            
            banana.runAction(flyoff) {
                banana.physicsBody?.categoryBitMask = GameCollisionCategoryBanana
                banana.physicsBody?.collisionBitMask = GameCollisionCategoryGround | GameCollisionCategoryPlayer
                if #available(iOS 9.0, OSX 10.11, *) {
                    banana.physicsBody!.contactTestBitMask = banana.physicsBody!.collisionBitMask
                }
            }
            self.bananas.insert(banana)
        }
        
        self.playerCharacter?.inHitAnimation = true
    }
    
}
