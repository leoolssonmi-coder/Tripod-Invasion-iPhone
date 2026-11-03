import UIKit
import ARKit
import SceneKit
import AVFoundation
import Combine
import simd

final class CoverMap {
    struct Key: Hashable { let x:Int;let y:Int;let z:Int;init(_ p:V3){x=Int(floor(p.x/0.25));y=Int(floor(p.y/0.25));z=Int(floor(p.z/0.25))} }
    struct Cell {var first:Double;var last:Double;var count:Int}
    private var cells:[Key:Cell]=[:];private var lastDepth:Double=0;private var eye=V3.zero
    func clear(){cells.removeAll();lastDepth=0}
    func update(_ frame:ARFrame){
        eye=V3(frame.camera.transform.columns.3.x,frame.camera.transform.columns.3.y,frame.camera.transform.columns.3.z)
        guard frame.timestamp-lastDepth>0.15,let depth=frame.sceneDepth else{return};lastDepth=frame.timestamp
        let pixel=depth.depthMap;let confidence=depth.confidenceMap
        CVPixelBufferLockBaseAddress(pixel,.readOnly);defer{CVPixelBufferUnlockBaseAddress(pixel,.readOnly)}
        if let confidence=confidence {CVPixelBufferLockBaseAddress(confidence,.readOnly)}
        defer{if let confidence=confidence{CVPixelBufferUnlockBaseAddress(confidence,.readOnly)}}
        guard let base=CVPixelBufferGetBaseAddress(pixel) else{return}
        let width=CVPixelBufferGetWidth(pixel);let height=CVPixelBufferGetHeight(pixel);let stride=CVPixelBufferGetBytesPerRow(pixel)
        let intrinsics=frame.camera.intrinsics;let size=frame.camera.imageResolution
        let sx=Float(width)/Float(size.width);let sy=Float(height)/Float(size.height)
        let fx=intrinsics[0][0]*sx;let fy=intrinsics[1][1]*sy;let cx=intrinsics[2][0]*sx;let cy=intrinsics[2][1]*sy
        let confBase=confidence.flatMap{CVPixelBufferGetBaseAddress($0)};let confStride=confidence.map{CVPixelBufferGetBytesPerRow($0)} ?? 0
        for y in Swift.stride(from:0,to:height,by:3){for x in Swift.stride(from:0,to:width,by:3){
            if let conf=confBase,conf.load(fromByteOffset:y*confStride+x,as:UInt8.self)<2{continue}
            let z=base.load(fromByteOffset:y*stride+x*4,as:Float.self)
            if !z.isFinite || z<0.25 || z>5{continue}
            let local=SIMD4<Float>((Float(x)-cx)*z/fx,-(Float(y)-cy)*z/fy,-z,1)
            let q=frame.camera.transform*local;let k=Key(V3(q.x,q.y,q.z))
            if var c=cells[k] {if frame.timestamp-c.last>2 && c.count<4{c.first=frame.timestamp;c.count=0};if c.last != frame.timestamp{c.count+=1};c.last=frame.timestamp;cells[k]=c}
            else {cells[k]=Cell(first:frame.timestamp,last:frame.timestamp,count:1)}
        }}
        cells=cells.filter{frame.timestamp-$0.value.last<240 && (abs(Float($0.key.x)*0.25-eye.x)<20 && abs(Float($0.key.z)*0.25-eye.z)<20)}
        if cells.count>18000{cells=Dictionary(uniqueKeysWithValues:cells.sorted{$0.value.last>$1.value.last}.prefix(16000).map{($0.key,$0.value)})}
    }
    func blocked(_ from:V3,_ to:V3)->Bool {
        if min(simd_distance(from,eye),simd_distance(to,eye))>24{return false}
        let a=simd_distance(from,eye)<simd_distance(to,eye) ? from:to
        let b=a==from ? to:from;let d=b-a;let distance=simd_length(d);let direction=unit(d)
        var t:Float=0.15
        while t<min(distance-0.15,26){if let c=cells[Key(a+direction*t)],c.count>=4 && c.last-c.first>=0.35{return true};t+=0.09}
        return false
    }
    func covered(sensor:V3,player:V3)->Bool {
        let delta=unit(sensor-player);let side=unit(V3(-delta.z,0,delta.x));var count=0
        for x in -1...1{for y in -1...1{if blocked(sensor,player+side*Float(x)*0.27+V3(0,Float(y)*0.28-0.18,0)){count+=1}}}
        return count>=7
    }
}

final class Microphone {
    private var engine:AVAudioEngine?;var level:Float=0;var active=false
    private var wanted=false;private var requesting=false
    func start(){
        wanted=true
        guard engine==nil && !requesting && AVAudioSession.sharedInstance().recordPermission != .denied else{return}
        requesting=true
        AVAudioSession.sharedInstance().requestRecordPermission{[weak self] granted in
            DispatchQueue.main.async{guard let self=self else{return};self.requesting=false;guard granted && self.wanted && self.engine==nil else{return};self.open()}
        }
    }
    private func open(){
        do{
            let audio=AVAudioSession.sharedInstance();try audio.setCategory(.playAndRecord,mode:.voiceChat,options:[.defaultToSpeaker,.allowBluetooth]);try audio.setActive(true)
            let engine=AVAudioEngine();let input=engine.inputNode;try? input.setVoiceProcessingEnabled(true)
            let format=input.outputFormat(forBus:0);guard format.channelCount>0,format.sampleRate>0 else{return}
            input.installTap(onBus:0,bufferSize:1024,format:format){[weak self] buffer,_ in
                guard let channel=buffer.floatChannelData?[0],buffer.frameLength>0 else{return}
                var sum:Float=0;for i in 0..<Int(buffer.frameLength){sum+=channel[i]*channel[i]}
                let db=20*log10(max(0.000001,sqrt(sum/Float(buffer.frameLength))));let n=clamp((db+48)/36,0,1)
                DispatchQueue.main.async{self?.level=n}
            }
            try engine.start();self.engine=engine;active=true
        }catch{stop()}
    }
    func stop(){wanted=false;engine?.inputNode.removeTap(onBus:0);engine?.stop();engine=nil;active=false;level=0}
}

final class GameController:NSObject,ObservableObject,ARSCNViewDelegate,ARSessionDelegate {
    let view=ARSCNView(frame:.zero);let game=Survival();let map=CoverMap();let microphone=Microphone()
    @Published var revision=0
    @Published var note="Tryck Starta för att spela."
    @Published var manualPause=false
    @Published var micEnabled=true
    @Published var night=true
    @Published var flashlight=false
    private var display:CADisplayLink?;private var last:CFTimeInterval=0;private var stable:Float=0;private var lastUI:Float=0
    private var rigs:[TripodRig]=[];private var lootNodes:[Int:SCNNode]=[:];private var planes:[UUID:ARPlaneAnchor]=[:]
    private let weapon=WeaponRig();private var traceNode:SCNNode?;private var suspended=false;private var waitingStart=false
    private var player=V3.zero;private var forward=V3(0,0,-1);private var lastDamage=3
    private var lastStage=RoundStage.menu
    override init(){
        super.init();view.delegate=self;view.session.delegate=self;view.scene=SCNScene();view.autoenablesDefaultLighting=true
        view.automaticallyUpdatesLighting=true;view.preferredFramesPerSecond=30
        let ambient=SCNLight();ambient.type = .ambient;ambient.intensity=500
        let light=SCNNode();light.light=ambient;view.scene.rootNode.addChildNode(light)
        display=CADisplayLink(target:self,selector:#selector(frame));display?.preferredFramesPerSecond=30;display?.add(to:.main,forMode:.common)
    }
    func begin(){
        guard ARWorldTrackingConfiguration.isSupported else{note="Den här enheten stöder inte ARKit.";revision+=1;return}
        AVCaptureDevice.requestAccess(for:.video){[weak self] allowed in DispatchQueue.main.async{
            guard let self=self else{return};guard allowed else{self.note="Tillåt Kamera i Inställningar för att spela.";self.revision+=1;return}
            self.waitingStart=true;self.manualPause=false;self.stable=0;self.map.clear();self.planes.removeAll();self.run(reset:true)
        }}
    }
    private func run(reset:Bool){
        let config=ARWorldTrackingConfiguration();config.planeDetection=[.horizontal,.vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth){config.frameSemantics.insert(.sceneDepth)}
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh){config.sceneReconstruction = .mesh}
        view.session.run(config,options:reset ? [.resetTracking,.removeExistingAnchors]:[]);suspended=false;last=0
    }
    func lifecycle(active:Bool){
        if active {if game.stage == .playing || waitingStart {stable=0;run(reset:false)}}
        else {suspended=true;view.session.pause();microphone.stop();last=0;setTorch(false)}
    }
    func action(_ name:String){
        guard !manualPause && !suspended else{return}
        switch name {
        case "shoot":game.shoot(player:player,forward:forward,blocked:map.blocked)
        case "reload":game.reload()
        case "switch":game.switchWeapon()
        case "collect":game.collect(player:player,blocked:map.blocked)
        default:game.toggle()
        };revision+=1
    }
    func setTorch(_ on:Bool){
        guard let camera=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back),camera.hasTorch else{note="Ficklampan är inte tillgänglig.";revision+=1;return}
        do{try camera.lockForConfiguration();defer{camera.unlockForConfiguration()};if on{try camera.setTorchModeOn(level:0.5)}else{camera.torchMode = .off};flashlight=on}catch{note="Ficklampan kunde inte starta under AR."}
    }
    @objc private func frame(_ link:CADisplayLink){
        guard !suspended,let frame=view.session.currentFrame else{return}
        let dt:Float=last==0 ? 0 : Float(min(0.1,link.timestamp-last));last=link.timestamp
        let p=frame.camera.transform.columns.3;player=V3(p.x,p.y,p.z)
        let f=frame.camera.transform.columns.2;forward = -V3(f.x,f.y,f.z)
        view.pointOfView?.camera?.zFar=450
        view.pointOfView?.camera?.zNear=0.05
        var tracked=false;switch frame.camera.trackingState {case .normal:tracked=true;default:break}
        // Unknown tracking always freezes both timer and damage; no old anchor is required.
        let ambient=frame.lightEstimate?.ambientIntensity ?? 100
        let reliable=tracked && ambient>15 && !manualPause
        stable=reliable ? stable+dt : 0
        if waitingStart && stable>=0.8 {
            game.start(player:player);waitingStart=false;lastDamage=3
            rigs.forEach{$0.root.removeFromParentNode()};rigs=(0..<4).map{_ in TripodRig()};rigs.forEach{view.scene.rootNode.addChildNode($0.root)}
        }
        if reliable{map.update(frame)}
        let canPlay=reliable && stable>=0.8
        game.step(dt:dt,player:player,noise:micEnabled && microphone.active ? microphone.level : 0,reliable:canPlay,cover:{[map,player] in map.covered(sensor:$0,player:player)},blocked:map.blocked)
        note=manualPause ? "Pausat" : canPlay ? "" : "AR väntar. Rikta kameran mot en tydlig, upplyst yta."
        if game.stage == .playing && canPlay && micEnabled {microphone.start()}else{microphone.stop()}
        if game.stage == .playing && canPlay {game.groundSupplies(dt:dt,ground:ground)}
        for (i,e) in game.enemies.enumerated() where i<rigs.count{rigs[i].update(e,time:game.elapsed)}
        if let camera=view.pointOfView,weapon.root.parent==nil{camera.addChildNode(weapon.root)}
        weapon.root.isHidden=game.stage != .playing || game.captured
        weapon.update(kind:game.selected,drawn:game.drawn,reloading:game.reloading,shotAge:game.shot?.age)
        for (id,n) in lootNodes where !game.supplies.contains(where:{$0.id==id}){n.removeFromParentNode();lootNodes.removeValue(forKey:id)}
        for item in game.supplies{
            if lootNodes[item.id]==nil{let n=cube(view.scene.rootNode,item.position,V3(0.6,0.44,0.44),material(item.weapon==nil ? .systemBlue:.systemGreen));lootNodes[item.id]=n}
            lootNodes[item.id]?.simdPosition=item.position
        }
        traceNode?.removeFromParentNode();traceNode=nil
        if let shot=game.shot{let n=rod(view.scene.rootNode,0.009,material(.systemYellow,glow:true));span(n,shot.from,shot.to);traceNode=n}
        if game.health<lastDamage{UIImpactFeedbackGenerator(style:.heavy).impactOccurred()};lastDamage=game.health
        if game.stage == .won || game.stage == .lost{map.clear();microphone.stop()}
        if game.elapsed-lastUI>0.08 || !canPlay || waitingStart || lastStage != game.stage {lastStage=game.stage;lastUI=game.elapsed;revision+=1}
    }
    private func ground(_ position:V3)->Float?{
        var heights:[Float]=[]
        for plane in planes.values where plane.alignment == .horizontal {
            let h=plane.transform.columns.3.y
            if h>player.y-0.8{continue}
            let local=simd_inverse(plane.transform)*SIMD4<Float>(position.x,h,position.z,1)
            let vertices=plane.geometry.boundaryVertices;guard vertices.count>=3 else{continue}
            var positive=false;var negative=false
            for i in vertices.indices{let a=vertices[i];let b=vertices[(i+1)%vertices.count];let cross=(b.x-a.x)*(local.z-a.z)-(b.z-a.z)*(local.x-a.x);if cross>0.001{positive=true};if cross < -0.001{negative=true}}
            if !(positive && negative){heights.append(h)}
        }
        return heights.min(by:{abs($0-position.y)<abs($1-position.y)})
    }
    func renderer(_ renderer:SCNSceneRenderer,didAdd node:SCNNode,for anchor:ARAnchor){updateAnchor(node,anchor)}
    func renderer(_ renderer:SCNSceneRenderer,didUpdate node:SCNNode,for anchor:ARAnchor){updateAnchor(node,anchor)}
    func renderer(_ renderer:SCNSceneRenderer,didRemove node:SCNNode,for anchor:ARAnchor){DispatchQueue.main.async{self.planes.removeValue(forKey:anchor.identifier)}}
    private func updateAnchor(_ node:SCNNode,_ anchor:ARAnchor){
        if let plane=anchor as? ARPlaneAnchor{DispatchQueue.main.async{self.planes[plane.identifier]=plane}}
        guard let mesh=anchor as? ARMeshAnchor else{return}
        let vertices=mesh.geometry.vertices;let faces=mesh.geometry.faces
        guard vertices.count>0 else{return}
        let data=Data(bytes:vertices.buffer.contents().advanced(by:vertices.offset),count:(vertices.count-1)*vertices.stride+12)
        let source=SCNGeometrySource(data:data,semantic:.vertex,vectorCount:vertices.count,usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:vertices.stride)
        let indices=Data(bytes:faces.buffer.contents(),count:faces.count*faces.indexCountPerPrimitive*faces.bytesPerIndex)
        let element=SCNGeometryElement(data:indices,primitiveType:.triangles,primitiveCount:faces.count,bytesPerIndex:faces.bytesPerIndex)
        let geometry=SCNGeometry(sources:[source],elements:[element]);let m=SCNMaterial();m.colorBufferWriteMask=[];m.writesToDepthBuffer=true;m.isDoubleSided=true;geometry.materials=[m]
        node.geometry=geometry;node.renderingOrder = -10
    }
    func sessionWasInterrupted(_ session:ARSession){DispatchQueue.main.async{self.stable=0;self.microphone.stop()}}
    func sessionInterruptionEnded(_ session:ARSession){DispatchQueue.main.async{self.stable=0;self.last=0}}
    func session(_ session:ARSession,didFailWithError error:Error){DispatchQueue.main.async{self.manualPause=true;self.note="AR kunde inte fortsätta: \(error.localizedDescription)";self.microphone.stop();self.revision+=1}}
}
