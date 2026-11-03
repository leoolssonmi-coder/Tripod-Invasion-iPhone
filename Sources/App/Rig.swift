import SceneKit
import simd

func material(_ color: UIColor, glow: Bool = false) -> SCNMaterial {
    let m = SCNMaterial(); m.diffuse.contents = color; m.metalness.contents = 0.65; m.roughness.contents = 0.45
    if glow {m.emission.contents=color}; return m
}
let armor = material(UIColor(white:0.23,alpha:1))
let metal = material(UIColor(white:0.4,alpha:1))
let blackMetal = material(UIColor(white:0.075,alpha:1))
let lens = material(.systemYellow,glow:true)
func sphere(_ parent: SCNNode, _ position: V3, _ scale: V3, _ mat: SCNMaterial) -> SCNNode {
    let g = SCNSphere(radius:1);g.segmentCount=12;g.materials=[mat]
    let n=SCNNode(geometry:g);n.simdPosition=position;n.simdScale=scale;parent.addChildNode(n);return n
}
func cube(_ parent: SCNNode, _ p: V3, _ size: V3, _ mat: SCNMaterial) -> SCNNode {
    let g=SCNBox(width:CGFloat(size.x),height:CGFloat(size.y),length:CGFloat(size.z),chamferRadius:0.01);g.materials=[mat]
    let n=SCNNode(geometry:g);n.simdPosition=p;parent.addChildNode(n);return n
}
func rod(_ parent: SCNNode, _ radius: CGFloat, _ mat: SCNMaterial) -> SCNNode {
    let g=SCNCylinder(radius:radius,height:1);g.radialSegmentCount=7;g.materials=[mat]
    let n=SCNNode(geometry:g);parent.addChildNode(n);return n
}
func span(_ node: SCNNode, _ a: V3, _ b: V3) {
    let d=b-a;node.simdPosition=(a+b)/2;node.simdScale=V3(1,simd_length(d),1)
    node.simdOrientation=simd_quatf(from:V3(0,1,0),to:unit(d))
}

final class TripodRig {
    let root=SCNNode();let head=SCNNode();let eyes=SCNNode()
    private var limbs: [[SCNNode]]=[]
    private var arms: [[SCNNode]]=[]
    private var muzzleNodes:[SCNNode]=[]
    private var beam=SCNNode()
    private var laser=SCNNode()
    init() {
        root.addChildNode(head);head.position=SCNVector3(0,9.4,0)
        _=sphere(head,V3(0,0,0),V3(0.95,0.43,0.65),armor)
        _=sphere(head,V3(0,0.28,-0.08),V3(0.62,0.34,0.48),metal)
        head.addChildNode(eyes);eyes.position=SCNVector3(0,-0.2,0.7)
        _=sphere(eyes,.zero,V3(0.13,0.11,0.06),lens)
        for side: Float in [-1,1] {_=sphere(head,V3(side*0.66,-0.3,0.2),V3(0.25,0.25,0.28),armor)}
        _=sphere(root,V3(0,8.25,0),V3(0.43,0.94,0.34),armor)
        for i in 0..<6 {_=sphere(root,V3(0,8.9-Float(i)*0.25,0),V3(0.4-Float(i)*0.035,0.09,0.33),metal)}
        for _ in 0..<3 {limbs.append([rod(root,0.13,armor),rod(root,0.085,metal),sphere(root,.zero,V3(0.19,0.21,0.19),blackMetal),sphere(root,.zero,V3(0.2,0.08,0.35),blackMetal)])}
        for _ in 0..<2 {arms.append([rod(head,0.10,armor),rod(head,0.075,blackMetal)]);muzzleNodes.append(sphere(head,.zero,V3(repeating:0.085),metal))}
        let light=SCNLight();light.type = .spot;light.color=UIColor(red:1,green:0.88,blue:0.64,alpha:1)
        light.intensity=750;light.spotInnerAngle=14;light.spotOuterAngle=20;light.attenuationStartDistance=1;light.attenuationEndDistance=28
        let spot=SCNNode();spot.light=light;eyes.addChildNode(spot);spot.eulerAngles.y = .pi
        let cone=SCNCone(topRadius:0,bottomRadius:CGFloat(tan(Float.pi/18)*28),height:28)
        let haze=SCNMaterial();haze.diffuse.contents=UIColor(red:1,green:0.9,blue:0.65,alpha:0.07);haze.isDoubleSided=true;haze.writesToDepthBuffer=false;haze.lightingModel = .constant
        cone.materials=[haze];beam=SCNNode(geometry:cone);beam.position=SCNVector3(0,0,14);beam.eulerAngles.x = -.pi/2;eyes.addChildNode(beam)
        laser=rod(root,0.045,material(.orange,glow:true));laser.isHidden=true
    }
    func update(_ e: Enemy, time: Float) {
        root.simdPosition=e.position;root.isHidden=e.health<=0
        let yaw=atan2(e.beam.x,e.beam.z);head.eulerAngles=SCNVector3(-asin(clamp(e.beam.y,-1,1)),yaw,0)
        let bodyYaw=atan2(e.facing.x,e.facing.z)
        func turn(_ p:V3)->V3 {V3(cos(bodyYaw)*p.x+sin(bodyYaw)*p.z,p.y,-sin(bodyYaw)*p.x+cos(bodyYaw)*p.z)}
        for i in 0..<3 {
            let a=Float(i)*2 * .pi/3 + .pi/2;let radial=V3(cos(a),0,sin(a))
            let phase=(e.walk/2.1+Float(i)/3).truncatingRemainder(dividingBy:1)
            let swing=clamp(phase/0.26,0,1)
            let lift:Float=e.moving && phase<0.26 ? sin(swing * .pi)*0.65 : 0
            let stride:Float = !e.moving ? 0 : phase<0.26 ? (swing-0.5)*1.554 : (0.5-(phase-0.26)/0.74)*1.554
            let hip=turn(radial*0.43+V3(0,7.4,0));let knee=turn(radial*1.45+V3(0,5.65+lift*0.22,0.1))
            let foot=turn(radial*2.25+V3(0,0.12+lift,stride))
            span(limbs[i][0],hip,knee);span(limbs[i][1],knee,foot);limbs[i][2].simdPosition=knee;limbs[i][3].simdPosition=foot
        }
        let attacking=e.phase == .charge || e.phase == .fire
        let laserAttack=e.attack == .heat || e.attack == .sweep
        for i in 0..<2 {
            let side:Float=i==0 ? -1 : 1
            let deploy:Float = attacking && laserAttack && e.arm==i ? (e.phase == .fire ? 1 : e.progress) : 0
            let shoulder=V3(side*0.84,-0.55,0);let elbow=V3(side*(1.3+0.4*deploy),-1.35+0.25*deploy,0.12+0.35*deploy)
            let localAim=head.simdConvertPosition(e.aim,from:nil)
            let direction=unit(V3(0,-0.6,0.8)*(1-deploy)+unit(localAim-elbow)*deploy)
            let recoil:Float=e.phase == .fire && e.arm==i ? sin(e.progress * .pi)*0.16 : 0
            let muzzle=elbow+direction*(0.85-recoil)
            span(arms[i][0],shoulder,elbow);span(arms[i][1],elbow,muzzle);muzzleNodes[i].simdPosition=muzzle
            muzzleNodes[i].geometry?.materials = [deploy>0 ? lens : metal]
        }
        beam.isHidden=e.health<=0
        laser.isHidden = !(e.phase == .fire && laserAttack && !e.hidden)
        if !laser.isHidden {
            let origin=root.simdConvertPosition(muzzleNodes[e.arm].simdWorldPosition,from:nil)
            var end=root.simdConvertPosition(e.aim,from:nil)
            if e.attack == .sweep {end.x += (e.progress-0.5)*8}
            span(laser,origin,end)
        }
    }
}

final class WeaponRig {
    let root=SCNNode();private var kind:Weapon?
    func update(kind:Weapon,drawn:Bool,reloading:Bool,shotAge:Float?) {
        if self.kind != kind {
            root.childNodes.forEach{$0.removeFromParentNode()};self.kind=kind
            if kind == .grenade {_=sphere(root,V3(0,0,0),V3(0.035,0.05,0.035),material(.systemGreen))}
            else {
                let length:Float=kind == .pistol ? 0.20 : 0.40
                _=cube(root,V3(0,0,0),V3(0.05,0.05,length),armor)
                _=cube(root,V3(0,-0.075,length*0.2),V3(0.045,0.11,0.05),blackMetal)
                _=cube(root,V3(0,0.035,-length*0.35),V3(0.009,0.012,0.01),metal)
                if kind == .rifle {_=cube(root,V3(0,-0.07,-0.02),V3(0.045,0.12,0.06),metal)}
                if kind == .rocket {let tube=rod(root,0.055,material(.systemGreen));span(tube,V3(0,0,-0.25),V3(0,0,0.25))}
            }
        }
        let kick=shotAge.map{exp(-$0*28)*0.035} ?? 0
        let target=SCNVector3(0.16,drawn ? (reloading ? -0.32 : -0.20) : -0.75,-0.45+kick)
        SCNTransaction.begin();SCNTransaction.animationDuration=0.18;root.position=target;SCNTransaction.commit()
    }
}
