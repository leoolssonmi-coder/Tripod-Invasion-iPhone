import SwiftUI
import ARKit
import simd

@main struct TripodApp:App {
    @StateObject private var controller=GameController()
    @Environment(\.scenePhase) private var phase
    var body:some Scene{WindowGroup{GameScreen(controller:controller).preferredColorScheme(.dark).onChange(of:phase){controller.lifecycle(active:$0 == .active)}}}
}
struct CameraView:UIViewRepresentable{
    let controller:GameController
    func makeUIView(context:Context)->ARSCNView{controller.view}
    func updateUIView(_ uiView:ARSCNView,context:Context){}
}
struct GameScreen:View{
    @ObservedObject var controller:GameController
    private var game:Survival{controller.game}
    private func plate<V:View>(@ViewBuilder _ content:()->V)->some View{content().padding(10).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:12))}
    var body:some View{
        ZStack{
            CameraView(controller:controller).ignoresSafeArea()
            if game.stage == .menu{
                Color.black.opacity(0.7).ignoresSafeArea()
                VStack(alignment:.leading,spacing:18){Text("TRIPOD").font(.largeTitle.bold());Text("INVASION AR • iPhone-testversion").foregroundStyle(.mint)
                    Text("Undvik fyra tripoders sökljus. Du har tre sekunder att hitta skydd när ljuset träffar dig. Högre ljud lockar dem.")
                    Text("Kameran och mikrofonen behandlas lokalt. Ingen satellitbana eller GPS i denna första iOS-version.").font(.footnote).foregroundStyle(.secondary)
                    Button("Starta kameran"){controller.begin()}.buttonStyle(.borderedProminent).tint(.mint)
                    Text(controller.note).font(.footnote)
                }.padding(28)
            }else{
                VStack{
                    HStack{
                        plate{HStack(spacing:14){Text(String(format:"%02d:%02d",max(0,180-Int(game.elapsed))/60,max(0,180-Int(game.elapsed))%60)).monospacedDigit();Text(status).font(.caption.bold()).foregroundStyle(game.hidden ? .mint:.white);Text(String(repeating:"●",count:game.health)).font(.caption).foregroundStyle(.red)}}
                        Spacer(minLength:8)
                        Menu{
                            Button(controller.manualPause ? "Fortsätt":"Pausa"){controller.manualPause.toggle()}
                            Button(controller.flashlight ? "Släck lampa":"Tänd lampa"){controller.setTorch(!controller.flashlight)}
                            Toggle("Mikrofon",isOn:$controller.micEnabled)
                            Text("iOS-testversion 0.1.0")
                        }label:{Text("•••").font(.title2).padding(8).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:12))}
                    }
                    if let e=game.enemies.max(by:{$0.exposure<$1.exposure}),e.exposure>0 && !e.detected{
                        Text("I SÖKLJUSET • GÖM DIG • \(Int(ceil(max(0,3-e.exposure)))) s").font(.caption.bold()).foregroundStyle(.orange).padding(6).background(.black.opacity(0.6),in:Capsule())
                    }
                    if game.captured{Text("FÅNGAD • TRYCK BRYT GREPP FEM GÅNGER").font(.caption.bold()).foregroundStyle(.orange)}
                    if game.enemies.contains(where:{$0.phase == .charge}){Text("ATTACK LADDAS • SÖK SKYDD").font(.caption.bold()).foregroundStyle(.orange)}
                    Spacer()
                    if game.paused || controller.manualPause{plate{Text(controller.note).font(.callout)}}
                    if game.stage == .won || game.stage == .lost{plate{VStack{Text(game.stage == .won ? "DU ÖVERLEVDE":"INVASIONEN TOG DIG").font(.title2.bold());Button("Spela igen"){controller.begin()}}}}
                    Spacer()
                    HStack{
                        if controller.microphone.active{Text("LJUD \(Int(controller.microphone.level*100))%").font(.caption2).foregroundStyle(controller.microphone.level>0.6 ? .orange:.mint)}
                        Spacer()
                        if let item=game.supplies.min(by:{simd_distance($0.position,cameraPosition)<simd_distance($1.position,cameraPosition)}),simd_distance(item.position,cameraPosition)<6{Text(item.weapon?.name ?? "Ammunitionslåda").font(.caption)}
                    }
                    plate{HStack{Button(game.drawn ? "\(game.selected.name) · dölj":"Ta fram vapen"){controller.action("toggle")};Spacer();Text("\(game.weapon.loaded)/30 • \(game.weapon.reserve) reserv").monospacedDigit().font(.caption)}}
                    HStack(spacing:6){control("Ladda om","reload");control("Byt vapen","switch");control("Plocka","collect");control(game.captured ? "Bryt grepp":game.drawn ? "Skjut":"Ta fram","shoot")}
                }.padding(.horizontal,14).padding(.vertical,6)
                if game.drawn && !game.paused && game.stage == .playing{Text("+").font(.system(size:18,weight:.light)).foregroundStyle(.white.opacity(0.65)).allowsHitTesting(false)}
            }
        }
    }
    private var status:String{game.paused ? "PAUS":game.captured ? "FÅNGAD":game.hidden ? "GÖMD":game.enemies.contains(where:{$0.detected}) ? "UPPTÄCKT":"OSEDD"}
    private var cameraPosition:V3{guard let p=controller.view.session.currentFrame?.camera.transform.columns.3 else{return .zero};return V3(p.x,p.y,p.z)}
    private func control(_ title:String,_ action:String)->some View{Button(title){controller.action(action)}.font(.caption).frame(maxWidth:.infinity,minHeight:46).background(action == "shoot" ? Color.red.opacity(0.65):Color.black.opacity(0.65),in:RoundedRectangle(cornerRadius:12)).disabled(game.paused || controller.manualPause || game.stage != .playing)}
}
