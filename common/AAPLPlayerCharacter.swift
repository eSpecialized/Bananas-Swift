//
//  AAPLPlayerCharacter.swift
//  Bananas
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/21.
//
//
/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:

  This class simulates the player character. It manages the character's animations and simulates movement and jumping.

 */

import SceneKit

enum WalkDirection: Int {
    case left = 0
    case right
}

@objc(AAPLPlayerCharacter)
class AAPLPlayerCharacter: AAPLSkinnedCharacter {
    
    // Animation State
    fileprivate var _inRunAnimation: Bool = false
    fileprivate var _inHitAnimation: Bool = false
    
    var walkSpeed: CGFloat = 0.0
    var jumpBoost: CGFloat = 0.0
    
    fileprivate var _walkDirection: WalkDirection = .right
    
    fileprivate(set) var collideSphere: SCNNode
    
    var jumping: Bool = false
    var launching: Bool = false
    
    var dustPoof: SCNParticleSystem
    var dustWalking: SCNParticleSystem
    
    enum AAPLCharacterAnimation: Int {
        case die = 0
        case run
        case jump
        case jumpFalling
        case jumpLand
        case idle
        case getHit
        case bored
        case runStart
        case runStop
        case count
    }
    
    fileprivate var _isWalking: Bool = false
    fileprivate var jumpForce: CGFloat = 0
    fileprivate var jumpDuration: CFTimeInterval = 0
    fileprivate var jumpForceOrig: CGFloat = 0
    fileprivate var dustWalkingBirthRate: CGFloat = 0
    
    fileprivate var _inJumpAnimation: Bool = false
    fileprivate var groundPlaneHeight: CGFloat = 0
    fileprivate var velocity: GLKVector3 = GLKVector3()
    fileprivate var baseWalkSpeed: CGFloat = 0
    
    fileprivate var cameraHelper: SCNNode
    fileprivate var ChangingDirection: Bool = false
    
    class func keyForAnimationType(_ animType: AAPLCharacterAnimation) -> String {
        
        switch animType {
        case .bored:
            return "bored-1"
        case .die:
            return "die-1"
        case .getHit:
            return "hit-1"
        case .idle:
            return "idle-1"
        case .jump:
            return "jump_start-1"
        case .jumpFalling:
            return "jump_falling-1"
        case .jumpLand:
            return "jump_land-1"
        case .run:
            return "run-1"
        case .runStart:
            return "run_start-1"
        case .runStop:
            return "run_stop-1"
        case .count:
            return ""
        }
    }
    
    override init(node characterNode: SCNNode) {
        self.cameraHelper = SCNNode()
        collideSphere = SCNNode()
        self.dustPoof = AAPLGameSimulation.loadParticleSystemWithName("dust")
        self.dustWalking = AAPLGameSimulation.loadParticleSystemWithName("dustWalking")
        super.init(node: characterNode)
        self.categoryBitMask = NodeCategoryLava
        
        // Setup walking parameters.
        velocity = GLKVector3Make(0, 0, 0)
        _isWalking = false
        ChangingDirection = false
        baseWalkSpeed = 0.0167
        jumpBoost = 0.0
        self.walkSpeed = baseWalkSpeed * 2
        self.jumping = false
        groundPlaneHeight = 0.0
        self.walkDirection = .right
        
        // Create a node to help position the camera and attach to self.
        self.addChildNode(self.cameraHelper)
        self.cameraHelper.position = SCNVector3Make(1000, 200, 0)
        
        // Create a capsule used for generic collision.
        collideSphere.position = SCNVector3Make(0, 80, 0)
        let geo = SCNCapsule(capRadius: 90, height: 160)
        let shape2 = SCNPhysicsShape(geometry: geo, options: nil)
        collideSphere.physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape2)
        
        // We only want to collide with bananas, coins, and coconuts. Ground collision is handled elsewhere.
        collideSphere.physicsBody!.collisionBitMask =
            GameCollisionCategoryBanana |
            GameCollisionCategoryCoin |
            GameCollisionCategoryCoconut |
        GameCollisionCategoryLava
        if #available(iOS 9.0, OSX 10.11, *) {
            collideSphere.physicsBody!.contactTestBitMask = collideSphere.physicsBody!.collisionBitMask
        }
        
        // Put ourself into the player category so other objects can limit their scope of collision checks.
        collideSphere.physicsBody!.categoryBitMask = GameCollisionCategoryPlayer
        self.addChildNode(collideSphere)
        
        // Load our dust poof.
        dustWalkingBirthRate = self.dustWalking.birthRate
        
        // Load the animations and store via a lookup table.
        self.setupIdleAnimation()
        self.setupRunAnimation()
        self.setupJumpAnimation()
        self.setupBoredAnimation()
        self.setupHitAnimation()
        
        self.playIdle(false)
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    //MARK: - Animation Setup
    
    fileprivate func setupIdleAnimation() {
        if let idleAnimation = self.loadAndCacheAnimation("art.scnassets/characters/explorer/idle",
            forKey: AAPLPlayerCharacter.keyForAnimationType(.idle))
        {
            idleAnimation.repeatCount = FLT_MAX
            idleAnimation.fadeInDuration = 0.15
            idleAnimation.fadeOutDuration = 0.15
        }
    }
    
    func setupRunAnimation() {
        let runKey = AAPLPlayerCharacter.keyForAnimationType(.run)
        let runStartKey = AAPLPlayerCharacter.keyForAnimationType(.runStart)
        let runStopKey = AAPLPlayerCharacter.keyForAnimationType(.runStop)
        
        let runAnim = self.loadAndCacheAnimation("art.scnassets/characters/explorer/run",
            forKey: runKey)!
        let runStartAnim = self.loadAndCacheAnimation("art.scnassets/characters/explorer/run_start",
            forKey: runStartKey)!
        let runStopAnim = self.loadAndCacheAnimation("art.scnassets/characters/explorer/run_stop",
            forKey: runStopKey)!
        runAnim.repeatCount = FLT_MAX
        runStartAnim.repeatCount = 0
        runStopAnim.repeatCount = 0
        
        runAnim.fadeInDuration = 0.05
        runAnim.fadeOutDuration = 0.05
        runStartAnim.fadeInDuration = 0.05
        runStartAnim.fadeOutDuration = 0.05
        runStopAnim.fadeInDuration = 0.05
        runStopAnim.fadeOutDuration = 0.05
        
        
        let stepLeftBlock: SCNAnimationEventBlock = {animation, animatedObject, playingBackward in
            AAPLGameSimulation.sim.playSound("leftstep.caf")
        }
        let stepRightBlock: SCNAnimationEventBlock = {animation, animatedObject, playingBackward in
            AAPLGameSimulation.sim.playSound("rightstep.caf")
        }
        
        let startWalkStateBlock: SCNAnimationEventBlock = {animation, animatedObject, playingBackward in
            if self.inRunAnimation {
                self._isWalking = true
            } else {
                self.mainSkeleton?.removeAnimation(forKey: runKey, fadeOutDuration: 0.15)
            }
        }
        let stopWalkStateBlock: SCNAnimationEventBlock = {animation, animatedObject, playingBackward in
            self._isWalking = false
            self.turnOffWalkingDust()
            if self.ChangingDirection {
                self._inRunAnimation = false
                self.inRunAnimation = true
                self.ChangingDirection = false
                self.walkDirection = (self.walkDirection == .left) ? .right : .left
            }
        }
        
        runStopAnim.animationEvents = [SCNAnimationEvent(keyTime: 1.0, block: stopWalkStateBlock)]
        runAnim.animationEvents = [SCNAnimationEvent(keyTime: 0.0, block: startWalkStateBlock),
            SCNAnimationEvent(keyTime: 0.25, block: stepRightBlock),
            SCNAnimationEvent(keyTime: 0.75, block: stepLeftBlock)]
    }
    
    fileprivate func setupJumpAnimation() {
        let jumpKey = AAPLPlayerCharacter.keyForAnimationType(.jump)
        let fallingKey = AAPLPlayerCharacter.keyForAnimationType(.jumpFalling)
        let landKey = AAPLPlayerCharacter.keyForAnimationType(.jumpLand)
        let idleKey = AAPLPlayerCharacter.keyForAnimationType(.idle)
        
        let jumpAnimation = self.loadAndCacheAnimation("art.scnassets/characters/explorer/jump_start", forKey: jumpKey)!
        let fallAnimation = self.loadAndCacheAnimation("art.scnassets/characters/explorer/jump_falling", forKey: fallingKey)!
        let landAnimation = self.loadAndCacheAnimation("art.scnassets/characters/explorer/jump_land", forKey: landKey)!
        
        jumpAnimation.fadeInDuration = 0.15
        jumpAnimation.fadeOutDuration = 0.15
        fallAnimation.fadeInDuration = 0.15
        landAnimation.fadeInDuration = 0.15
        landAnimation.fadeOutDuration = 0.15
        
        jumpAnimation.repeatCount = 0
        fallAnimation.repeatCount = 0
        landAnimation.repeatCount = 0
        
        jumpForceOrig = 7.0
        jumpForce = jumpForceOrig
        jumpDuration = jumpAnimation.duration
        let leaveGroundBlock: SCNAnimationEventBlock = {animation, animatedObject, playingBackward in
            self.velocity = GLKVector3Add(self.velocity, GLKVector3Make(0, Float(self.jumpForce * 2.1), 0))
            self.launching = false
            self.inJumpAnimation = false
        }
        let pause: SCNAnimationEventBlock = {animation, animatedObject, playingBackward in
            self.mainSkeleton?.pauseAnimation(forKey: fallingKey)
        }
        
        jumpAnimation.animationEvents = [SCNAnimationEvent(keyTime: 0.25, block: leaveGroundBlock)]
        fallAnimation.animationEvents = [SCNAnimationEvent(keyTime: 0.5, block: pause)]
        
        // Animation Sequence is to Jump -> Fall -> Land -> Idle.
        self.chainAnimation(jumpKey, toAnimation: fallingKey)
        self.chainAnimation(landKey, toAnimation: idleKey)
    }
    
    fileprivate func setupBoredAnimation() {
        if let animation = self.loadAndCacheAnimation("art.scnassets/characters/explorer/bored",
            forKey: AAPLPlayerCharacter.keyForAnimationType(.bored))
        {
            animation.repeatCount = FLT_MAX
        }
    }
    
    fileprivate func setupHitAnimation() {
        if let animation = self.loadAndCacheAnimation("art.scnassets/characters/explorer/hit", forKey: AAPLPlayerCharacter.keyForAnimationType(.getHit))
        {
            animation.repeatCount = FLT_MAX
        }
    }
    
    //MARK: -
    
    var running: Bool {
        return _isWalking
    }
    
    fileprivate func playIdle(_ stop: Bool) {
        self.turnOffWalkingDust()
        
        let anim = self.cachedAnimationForKey(AAPLPlayerCharacter.keyForAnimationType(.idle))!
        anim.repeatCount = MAXFLOAT
        anim.fadeInDuration = 0.1
        anim.fadeOutDuration = 0.1
        self.mainSkeleton?.addAnimation(anim, forKey: AAPLPlayerCharacter.keyForAnimationType(.idle))
    }
    
    fileprivate func playLand() {
        let fallKey = AAPLPlayerCharacter.keyForAnimationType(.jumpFalling)
        let key = AAPLPlayerCharacter.keyForAnimationType(.jumpLand)
        let anim = self.cachedAnimationForKey(key)!
        anim.timeOffset = 0.65
        self.mainSkeleton?.removeAnimation(forKey: fallKey, fadeOutDuration: 0.15)
        self.inJumpAnimation = false
        if _isWalking {
            _inRunAnimation = false
            self.inRunAnimation = true
        } else {
            self.mainSkeleton?.addAnimation(anim, forKey: key)
        }
        
        AAPLGameSimulation.sim.playSound("Land.wav")
    }
    
    override func update(_ deltaTime: TimeInterval) {
        var mtx = SCNMatrix4ToGLKMatrix4(self.transform)
        
        let gravity = GLKVector3Make(0, -90, 0)
        let gravitystep = GLKVector3MultiplyScalar(gravity, Float(deltaTime))
        
        velocity = GLKVector3Add(velocity, gravitystep)
        
        let minMovement = GLKVector3Make(0, -50, 0)
        let maxMovement = GLKVector3Make(100, 100, 100)
        velocity = GLKVector3Maximum(velocity, minMovement)
        velocity = GLKVector3Minimum(velocity, maxMovement)
        
        mtx = GLKMatrix4TranslateWithVector3(mtx, velocity)
        groundPlaneHeight = self.getGroundHeight(mtx)
        
        if CGFloat(mtx.m31) < groundPlaneHeight {
            if !self.launching && velocity.y < 0.0 {
                if self.jumping {
                    self.jumping = false
                    self.addParticleSystem(self.dustPoof)
                    self.dustPoof.loops = false
                    self.playLand()
                    jumpBoost = 0.0
                }
            }
            
            // tie to ground.
            mtx.m.13 = Float(groundPlaneHeight) //###13=4*3+1->m31
            
            velocity.v.1 = 0.0 //###(.0=x,.1=y,.2=z)
        }
        
        self.transform = SCNMatrix4FromGLKMatrix4(mtx)
        
        //-- move the camera
        if let camera = AAPLGameSimulation.sim.gameLevel.camera?.parent {
            
            //interpolate
            let pos = SCNVector3Make(self.position.x + ((self.walkDirection == .right) ? 250 : -250),
                (self.position.y + 261) - (0.85 * (self.position.y - SCNVectorFloat(groundPlaneHeight))),
                (self.position.z + 1500))
            let desiredTransform = AAPLMatrix4SetPosition(camera.transform, pos)
            camera.transform = AAPLMatrix4Interpolate(camera.transform, desiredTransform, 0.025)
        }
    }
    
    /*! Given our current location,
    shoot a ray downward to collide with our ground mesh or lava mesh
    */
    fileprivate func getGroundHeight(_ mtx: GLKMatrix4) -> CGFloat {
        let start = SCNVector3Make(SCNVectorFloat(mtx.m30), SCNVectorFloat(mtx.m31) + 1000, SCNVectorFloat(mtx.m32))
        let end = SCNVector3Make(SCNVectorFloat(mtx.m30), SCNVectorFloat(mtx.m31) - 3000, SCNVectorFloat(mtx.m32))
        
        let hits = AAPLGameSimulation.sim.physicsWorld.rayTestWithSegment(from: start,
            to: end,
            options: [SCNPhysicsWorld.TestOption.collisionBitMask: GameCollisionCategoryGround | GameCollisionCategoryLava,
                SCNPhysicsWorld.TestOption.searchMode: SCNPhysicsWorld.TestSearchMode.closest])
        if !hits.isEmpty {
            // take the first hit. make that the ground.
            for result in hits {
                if (result.node.physicsBody?.categoryBitMask ?? 0) & ~(GameCollisionCategoryGround|GameCollisionCategoryLava) != 0 {
                    continue
                }
                return CGFloat(result.worldCoordinates.y)
            }
        }
        
        // 0 is ground if we didn't hit anything.
        return 0
        
    }
    
    fileprivate func AAPLMatrix4Interpolate(_ scnm0: SCNMatrix4, _ scnmf: SCNMatrix4, _ factor: CGFloat) -> SCNMatrix4 {
        let m0 = SCNMatrix4ToGLKMatrix4(scnm0)
        let mf = SCNMatrix4ToGLKMatrix4(scnmf)
        let p0 = GLKMatrix4GetColumn(m0, 3)
        let pf = GLKMatrix4GetColumn(mf, 3)
        let q0 = GLKQuaternionMakeWithMatrix4(m0)
        let qf = GLKQuaternionMakeWithMatrix4(mf)
        
        let pTmp = GLKVector4Lerp(p0, pf, Float(factor))
        let qTmp = GLKQuaternionSlerp(q0, qf, Float(factor))
        let rTmp = GLKMatrix4MakeWithQuaternion(qTmp)
        
        let transform = SCNMatrix4(m11: SCNVectorFloat(rTmp.m00), m12: SCNVectorFloat(rTmp.m01), m13: SCNVectorFloat(rTmp.m02), m14: 0.0,
            m21: SCNVectorFloat(rTmp.m10), m22: SCNVectorFloat(rTmp.m11), m23: SCNVectorFloat(rTmp.m12), m24: 0.0,
            m31: SCNVectorFloat(rTmp.m20), m32: SCNVectorFloat(rTmp.m21), m33: SCNVectorFloat(rTmp.m22), m34: 0.0,
            m41: SCNVectorFloat(pTmp.x),   m42: SCNVectorFloat(pTmp.y),   m43: SCNVectorFloat(pTmp.z), m44: 1.0)
        
        return transform
    }
    
    /*! Jump with variable heights based on how many times this method gets called.
    */
    func performJumpAndStop(_ stop: Bool) {
        jumpForce = 13.0
        if stop {
            return
        }
        
        jumpBoost += 0.0005
        let maxBoost = self.walkSpeed * 2.0
        if jumpBoost > maxBoost {
            jumpBoost = maxBoost
        } else {
            velocity.v.1 += 0.55 //### v.1=y
        }
        
        if !self.jumping {
            self.jumping = true
            self.launching = true
            self.inJumpAnimation = true
        }
    }
    
    var inJumpAnimation: Bool {
        get {
            return _inJumpAnimation
        }
        set(jumpAnimState) {
            if _inJumpAnimation == jumpAnimState {
                return
            }
            
            _inJumpAnimation = jumpAnimState
            if _inJumpAnimation {
                // Launching YES means we are in the preflight jump animation.
                self.launching = true
                
                let anim = self.cachedAnimationForKey(AAPLPlayerCharacter.keyForAnimationType(.jump))!
                self.mainSkeleton?.removeAllAnimations()
                self.mainSkeleton?.addAnimation(anim, forKey: AAPLPlayerCharacter.keyForAnimationType(.jump))
                self.turnOffWalkingDust()
            } else {
                self.launching = false
            }
        }
    }
    
    var inRunAnimation: Bool {
        get {
            return _inRunAnimation
        }
        set(runAnimState) {
            if _inRunAnimation == runAnimState {
                return
            }
            _inRunAnimation = runAnimState
            
            // If we are running, then
            if _inRunAnimation {
                self.walkSpeed = baseWalkSpeed * 2
                
                let runKey = AAPLPlayerCharacter.keyForAnimationType(.run)
                let idleKey = AAPLPlayerCharacter.keyForAnimationType(.idle)
                
                let runAnim = self.cachedAnimationForKey(runKey)!
                self.mainSkeleton?.removeAnimation(forKey: idleKey, fadeOutDuration: 0.15)
                self.mainSkeleton?.addAnimation(runAnim, forKey: runKey)
                // add or turn on the flow of dust particles.
                if !(self.particleSystems?.contains(self.dustWalking) ?? false) {
                    self.addParticleSystem(self.dustWalking)
                } else {
                    self.dustWalking.birthRate = dustWalkingBirthRate
                }
            } else {
                // Fade out run and move to run stop.
                let runKey = AAPLPlayerCharacter.keyForAnimationType(.run)
                let runStopKey = AAPLPlayerCharacter.keyForAnimationType(.idle)
                let runStopAnim = self.cachedAnimationForKey(runStopKey)!
                runStopAnim.fadeInDuration = 0.15
                runStopAnim.fadeOutDuration = 0.15
                self.mainSkeleton?.removeAnimation(forKey: runKey, fadeOutDuration: 0.15)
                self.mainSkeleton?.addAnimation(runStopAnim, forKey: runStopKey)
                self.walkSpeed = baseWalkSpeed
                self.turnOffWalkingDust()
                _isWalking = false
            }
        }
    }
    
    fileprivate func turnOffWalkingDust() {
        // Stop the flow of dust by turning the birthrate to 0.
        if self.particleSystems?.contains(self.dustWalking) ?? false {
            self.dustWalking.birthRate = 0
        }
    }
    
    var walkDirection: WalkDirection {
        get {
            return _walkDirection
        }
        set(newDirection) {
            // If we changed directions and are already walking
            // then play the run stop animation once.
            if newDirection != _walkDirection && _isWalking && !self.launching && !self.jumping {
                if !self.ChangingDirection {
                    self.mainSkeleton?.removeAllAnimations()
                    let key = AAPLPlayerCharacter.keyForAnimationType(.runStop)
                    let anim = self.cachedAnimationForKey(key)!
                    self.mainSkeleton?.addAnimation(anim, forKey: key)
                    self.ChangingDirection = true
                    self.walkSpeed = baseWalkSpeed
                }
            } else {
                _walkDirection = newDirection
            }
        }
    }
    
    var inHitAnimation: Bool {
        get {
            return _inHitAnimation
        }
        set(GetHitAnimState) {
            _inHitAnimation = GetHitAnimState
            
            // Play the get hit animation.
            let anim = self.cachedAnimationForKey(AAPLPlayerCharacter.keyForAnimationType(.getHit))!
            anim.repeatCount = 0
            anim.fadeInDuration = 0.15
            anim.fadeOutDuration = 0.15
            self.mainSkeleton?.addAnimation(anim, forKey: AAPLPlayerCharacter.keyForAnimationType(.getHit))
            
            _inHitAnimation = false
            
            AAPLGameSimulation.sim.playSound("coconuthit.caf")
        }
    }
    
}
