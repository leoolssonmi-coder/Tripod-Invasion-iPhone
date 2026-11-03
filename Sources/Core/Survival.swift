import Foundation
import simd

typealias V3 = SIMD3<Float>
func unit(_ v: V3) -> V3 { let n = simd_length(v); return n > 0.0001 ? v / n : V3(0, 0, -1) }
func flat(_ v: V3) -> V3 { V3(v.x, 0, v.z) }
func clamp(_ v: Float, _ a: Float, _ b: Float) -> Float { min(b, max(a, v)) }
enum RoundStage { case menu, playing, won, lost }
enum Attack: Int { case heat, sweep, tentacle, stomp }
enum Phase { case patrol, search, charge, fire }
enum Weapon: Int, CaseIterable {
    case pistol, rifle, rocket, grenade
    var name: String { ["Pistol", "Automatgevär", "Raketvapen", "Granater"][rawValue] }
    var interval: Float { [0.28, 0.12, 0.9, 0.8][rawValue] }
    var reload: Float { [1.15, 1.5, 1.8, 0.8][rawValue] }
    var damage: Float { [12, 16, 65, 60][rawValue] }
    var shieldDamage: Float { [5, 8, 55, 40][rawValue] }
}
struct Stock { var owned = false; var loaded = 0; var reserve = 0 }
struct Supply { let id: Int; var position: V3; let weapon: Weapon? }
struct Enemy {
    let id: Int
    var position: V3
    var home: V3
    var beam: V3
    var facing: V3
    var health: Float = 100
    var shield: Float = 100
    var exposure: Float = 0
    var detected = false
    var hidden = false
    var memory: V3? = nil
    var seen: Float = -100
    var heardUntil: Float = 0
    var hearAt: Float = 0
    var phase = Phase.patrol
    var attack = Attack.heat
    var attackAt: Float = -100
    var nextAttack: Float = 12
    var attackCount = 0
    var hitAttempted = false
    var aim = V3.zero
    var progress: Float = 0
    var walk: Float = 0
    var moving = false
    var hitAt: Float = -100
    var stunUntil: Float = 0
    var arm: Int { max(0, attackCount - 1) % 2 }
    var sensor: V3 { position + V3(0, 7.6, 0) }
}
struct Projectile { var origin: V3; var velocity: V3; var age: Float = 0; var position: V3 { origin + velocity * age + V3(0, -2.45 * age * age, 0) } }
struct Shot { var from: V3; var to: V3; var age: Float = 0 }

final class Survival {
    private let random: () -> Float
    init(random: @escaping () -> Float = { Float.random(in: 0..<1) }) { self.random = random }
    private(set) var stage = RoundStage.menu
    private(set) var enemies: [Enemy] = []
    private(set) var supplies: [Supply] = []
    private(set) var stocks = Array(repeating: Stock(), count: 4)
    private(set) var selected = Weapon.pistol
    private(set) var elapsed: Float = 0
    private(set) var health = 3
    private(set) var drawn = true
    private(set) var paused = false
    private(set) var shot: Shot?
    private(set) var projectiles: [Projectile] = []
    private(set) var message = ""
    private(set) var reloadUntil: Float = 0
    private var fireAt: Float = 0
    private var groupAt: Float = 0
    private var owner: Int? = nil
    private var lootOrigin = V3.zero
    private var observerPosition = V3.zero
    private var supplyID = 0
    private var captor: Int? = nil
    private var captureUntil: Float = 0
    private var escapes = 0
    private var escapeAt: Float = 0
    var captured: Bool { captor != nil }
    var weapon: Stock { stocks[selected.rawValue] }
    var defeated: Int { enemies.filter { $0.health <= 0 }.count }
    var reloading: Bool { reloadUntil > elapsed }
    var hidden: Bool {
        let threats = enemies.filter { $0.health > 0 && simd_distance($0.position, observerPosition) < 35 }
        return !captured && !threats.isEmpty && threats.allSatisfy { $0.hidden }
    }
    static func inBeam(_ enemy: Enemy, _ player: V3) -> Bool {
        let d = player - enemy.sensor
        return simd_length(d) <= 28 && simd_dot(unit(d), unit(enemy.beam)) >= cos(.pi / 18)
    }
    func start(player: V3) {
        elapsed = 0; health = 3; drawn = true; paused = false; shot = nil; captor = nil
        owner = nil; groupAt = 0; fireAt = 0; reloadUntil = 0; selected = .pistol
        stocks = Array(repeating: Stock(), count: 4); stocks[0] = Stock(owned: true, loaded: 30, reserve: 300)
        enemies.removeAll(); supplies.removeAll(); projectiles.removeAll(); supplyID = 0
        let rotation = random() * .pi * 2
        for id in 0..<4 {
            let a = rotation + Float(id) * .pi / 2 + (random() - 0.5) * 0.45
            let radius = 100 + random() * 200
            let p = player + V3(sin(a) * radius, -1.6, cos(a) * radius)
            enemies.append(Enemy(id: id, position: p, home: p, beam: unit(V3(sin(a + .pi + 1), -0.3, cos(a + .pi + 1))), facing: unit(flat(player - p))))
        }
        lootOrigin = player; observerPosition = player; seed(player); stage = .playing; message = "Undvik sökljusen."
    }
    func toggle() { if stage == .playing && !paused && !captured { drawn.toggle() } }
    func switchWeapon() {
        guard stage == .playing && !paused else { return }
        for step in 1...4 { let i = (selected.rawValue + step) % 4; if stocks[i].owned { selected = Weapon(rawValue: i)!; reloadUntil = 0; break } }
    }
    func reload() {
        guard stage == .playing && !paused && drawn && !reloading && weapon.loaded < 30 && weapon.reserve > 0 else { return }
        reloadUntil = elapsed + selected.reload
    }
    func collect(player: V3, blocked: (V3,V3) -> Bool) {
        guard stage == .playing && !paused && !captured,
              let i = supplies.indices.min(by: { simd_distance(supplies[$0].position, player) < simd_distance(supplies[$1].position, player) }),
              simd_distance(supplies[i].position, player) <= 6, !blocked(player, supplies[i].position) else { return }
        let item = supplies[i]
        if let w = item.weapon {
            if !stocks[w.rawValue].owned { stocks[w.rawValue] = Stock(owned: true, loaded: 30, reserve: 300) }
            else { stocks[w.rawValue].reserve = min(1000, stocks[w.rawValue].reserve + 300) }
            selected = w; reloadUntil = 0
        } else {
            guard stocks.contains(where: { $0.owned && $0.reserve < 1000 }) else { return }
            for k in stocks.indices where stocks[k].owned { stocks[k].reserve = min(1000, stocks[k].reserve + 300) }
        }
        supplies.remove(at: i)
    }
    func groundSupplies(dt: Float, ground: (V3) -> Float?) {
        for i in supplies.indices {
            if let y = ground(supplies[i].position), y.isFinite {
                supplies[i].position.y += clamp(y + 0.22 - supplies[i].position.y, -dt * 1.5, dt * 1.5)
            }
        }
    }
    func shoot(player: V3, forward: V3, blocked: (V3,V3) -> Bool) {
        guard stage == .playing && !paused else { return }
        if captured {
            guard elapsed >= escapeAt else { return }; escapeAt = elapsed + 0.25
            if selected == .grenade && weapon.loaded > 0, let id = captor {
                stocks[selected.rawValue].loaded -= 1; enemies[id].health = 0; captor = nil; groupAt = elapsed + 5
            } else { escapes += 1; if escapes >= 5 { captor = nil; groupAt = elapsed + 5 } }
            return
        }
        if !drawn { drawn = true; return }
        guard elapsed >= fireAt && !reloading && weapon.loaded > 0 else { return }
        stocks[selected.rawValue].loaded -= 1; fireAt = elapsed + selected.interval
        let direction = unit(forward)
        if selected == .grenade { projectiles.append(Projectile(origin: player, velocity: direction * 8 + V3(0,3.5,0))); return }
        var nearest: Int?; var best: Float = 120; var end = player + direction * best
        for i in enemies.indices where enemies[i].health > 0 {
            let e = enemies[i]; let planar = direction.x * direction.x + direction.z * direction.z
            if planar < 0.01 { continue }
            let t = ((e.position.x-player.x)*direction.x + (e.position.z-player.z)*direction.z) / planar
            let hit = player + direction * t
            if t > 0.5 && t < best && hit.y >= e.position.y && hit.y <= e.position.y + 10 && simd_length(flat(hit-e.position)) < 1.05 + t*0.025 { nearest = i; best = t; end = hit }
        }
        if let i = nearest, !blocked(player, end) { hurt(i, weapon: selected) }
        shot = Shot(from: player, to: end)
    }
    private func hurt(_ i: Int, weapon: Weapon) {
        enemies[i].hitAt = elapsed
        if enemies[i].shield > 0 {
            enemies[i].shield = max(0, enemies[i].shield - weapon.shieldDamage)
            if enemies[i].shield == 0 { enemies[i].stunUntil = elapsed + 2 }
        } else { enemies[i].health = max(0, enemies[i].health - weapon.damage) }
    }
    private func seed(_ player: V3) {
        for i in 0..<5 {
            let a = random() * .pi * 2; let distance: Float = i == 0 ? 5 : 12 + Float(i)*6
            let kind: Weapon? = random() < 0.2 ? nil : Weapon(rawValue: 1 + supplyID % 3)
            supplies.append(Supply(id: supplyID, position: player + V3(sin(a)*distance,-1.38,cos(a)*distance), weapon: kind)); supplyID += 1
        }
    }
    func step(dt input: Float, player: V3, noise: Float, reliable: Bool, cover: (V3) -> Bool, blocked: (V3,V3) -> Bool) {
        guard stage == .playing else { return }
        paused = !reliable; observerPosition = player; guard reliable else { return }
        let dt = clamp(input,0,0.1); elapsed += dt
        if var trace = shot { trace.age += dt; shot = trace.age > 0.18 ? nil : trace }
        if reloadUntil > 0 && elapsed >= reloadUntil {
            let n = min(30-weapon.loaded, weapon.reserve); stocks[selected.rawValue].loaded += n; stocks[selected.rawValue].reserve -= n; reloadUntil = 0
        }
        if simd_distance(player,lootOrigin) > 20 { seed(player); lootOrigin = player }
        supplies.removeAll { simd_distance($0.position,player)>90 }; if supplies.count>12 { supplies.removeFirst(supplies.count-12) }
        for i in projectiles.indices.reversed() {
            projectiles[i].age += dt
            if projectiles[i].age >= 2 {
                let p = projectiles.remove(at:i).position
                for j in enemies.indices where enemies[j].health>0 && simd_length(flat(enemies[j].position-p))<7 && !blocked(p,enemies[j].position+V3(0,4,0)) { hurt(j,weapon:.grenade) }
            }
        }
        if captured && elapsed > captureUntil { captor = nil; health -= 1; groupAt = elapsed+5 }
        for i in enemies.indices {
            var e = enemies[i]; e.moving = false
            if e.health<=0 { e.detected=false; e.phase = .patrol; enemies[i]=e; if owner==i {owner=nil;groupAt=elapsed+10}; continue }
            e.hidden = cover(e.sensor)
            if elapsed-e.hitAt>8 && e.shield>0 {e.shield=min(100,e.shield+dt*3)}
            if elapsed-e.seen>5 && elapsed>e.heardUntil {e.memory=nil}
            let a = Float(i)*1.57 + sin(elapsed*0.12+Float(i))*0.5
            let target = e.memory.map { unit($0-e.sensor) } ?? (e.exposure>0 ? e.beam : unit(V3(sin(a),-0.3,cos(a))))
            let angle = acos(clamp(simd_dot(unit(e.beam),target),-1,1)); let mix = min(1,dt*0.35/max(angle,0.001))
            e.beam = unit(e.beam*(1-mix)+target*mix)
            let sees = elapsed>=e.stunUntil && !e.hidden && Self.inBeam(e,player) && !blocked(e.sensor,player)
            e.exposure = sees ? min(3.1,e.exposure+dt) : 0; e.detected = sees && e.exposure>=3
            if e.detected {e.memory=player;e.seen=elapsed}
            let hearing = (4+clamp(noise,0,1)*31)*(e.hidden ? 0.45 : 1)
            if !e.detected && noise>0.2 && elapsed>=e.hearAt && simd_distance(e.position,player)<hearing {
                e.memory=player+V3(sin(elapsed+Float(i))*5,0,cos(elapsed+Float(i))*5);e.heardUntil=elapsed+4;e.hearAt=elapsed+3
            }
            if e.attackAt>=0 && (elapsed-e.seen>1.5 || e.hidden || elapsed<e.stunUntil || captured) {e.attackAt = -100;e.nextAttack=elapsed+10;if owner==i {owner=nil;groupAt=elapsed+5}}
            let distance = simd_length(flat(player-e.position))
            if e.attackAt<0 && e.detected && !e.hidden && !captured && elapsed>=e.stunUntil && distance<26 && elapsed>=e.nextAttack && owner==nil && elapsed>=groupAt {
                e.attack = distance<5.5 ? .stomp : distance<14 ? .tentacle : e.attackCount%3==1 ? .sweep : .heat
                e.aim=e.memory ?? player;e.attackAt=elapsed;e.attackCount+=1;e.hitAttempted=false;owner=i
            }
            e.phase = e.memory == nil ? .patrol : .search
            let age = elapsed-e.attackAt
            if e.attackAt>=0 {
                if age>=4.1 {e.attackAt = -100;e.nextAttack=elapsed+28;owner=nil;groupAt=elapsed+10}
                else {e.phase = age<3.5 ? .charge : .fire;e.progress = age<3.5 ? age/3.5 : (age-3.5)/0.6}
            }
            if e.phase == .fire && !e.hitAttempted {
                e.hitAttempted=true
                let range: Float = e.attack == .stomp ? 5.5 : e.attack == .tentacle ? 14 : 26
                if elapsed-e.seen<1 && !e.hidden && !captured && distance<=range && simd_distance(flat(player-e.aim),.zero)<(e.attack == .sweep ? 3.5 : 2.5) && !blocked(e.sensor,player) {
                    if e.attack == .tentacle {captor=i;captureUntil=elapsed+7;escapes=0}
                    else {health-=1}
                }
            }
            if (e.phase == .patrol || e.phase == .search) && !captured && elapsed>=e.stunUntil {
                let destination = e.memory ?? (e.home+V3(sin(elapsed*0.055+Float(i))*18,0,cos(elapsed*0.055+Float(i))*18))
                let d = flat(destination-e.position)
                if simd_length(d) > (e.memory == nil ? 1 : 8) {
                    let direct=unit(d);let side=V3(-direct.z,0,direct.x)
                    for direction in [direct,side,-side] {
                        let next=e.position+direction*(e.memory == nil ? 0.85 : 1.1)*dt
                        if !blocked(e.position+V3(0,1,0),next+V3(0,1,0)+direction*1.2) {e.walk+=simd_distance(e.position,next);e.position=next;e.facing=direction;e.moving=true;break}
                    }
                }
            }
            enemies[i]=e
        }
        if health<=0 {health=0;stage = .lost}
        else if elapsed>=180 || defeated==4 {stage = .won}
    }
}
