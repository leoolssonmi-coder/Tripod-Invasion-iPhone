import XCTest
import simd
@testable import TripodCore

final class SurvivalTests:XCTestCase {
    func make()->Survival{let game=Survival(random:{0.4});game.start(player:.zero);return game}
    func advance(_ game:Survival,_ n:Int=20,reliable:Bool=true){for _ in 0..<n{game.step(dt:0.1,player:.zero,noise:0,reliable:reliable,cover:{_ in true},blocked:{_,_ in false})}}
    func testSpawnBoundsAndCount(){let g=make();XCTAssertEqual(g.enemies.count,4);for e in g.enemies{XCTAssertGreaterThanOrEqual(simd_length(flat(e.position)),100);XCTAssertLessThanOrEqual(simd_length(flat(e.position)),300)}}
    func testStarterStock(){let g=make();XCTAssertEqual(g.weapon.loaded,30);XCTAssertEqual(g.weapon.reserve,300)}
    func testHolsterPreservesAmmunition(){let g=make();g.toggle();XCTAssertFalse(g.drawn);XCTAssertEqual(g.weapon.loaded,30);g.shoot(player:.zero,forward:V3(0,0,-1),blocked:{_,_ in false});XCTAssertTrue(g.drawn);XCTAssertEqual(g.weapon.loaded,30)}
    func testShotConsumesOneAndRateLimited(){let g=make();g.shoot(player:.zero,forward:V3(0,0,-1),blocked:{_,_ in false});g.shoot(player:.zero,forward:V3(0,0,-1),blocked:{_,_ in false});XCTAssertEqual(g.weapon.loaded,29)}
    func testReloadTransfersReserve(){let g=make();g.shoot(player:.zero,forward:V3(0,0,-1),blocked:{_,_ in false});g.reload();advance(g);XCTAssertEqual(g.weapon.loaded,30);XCTAssertEqual(g.weapon.reserve,299)}
    func testTrackingLossFreezesTimeAndDamage(){let g=make();advance(g,100,reliable:false);XCTAssertEqual(g.elapsed,0);XCTAssertEqual(g.health,3);XCTAssertTrue(g.paused)}
    func testPausedCannotShoot(){let g=make();advance(g,1,reliable:false);g.shoot(player:.zero,forward:V3(0,0,-1),blocked:{_,_ in false});XCTAssertEqual(g.weapon.loaded,30)}
    func testUnseenPlayerIsNotAcquired(){let g=make();advance(g,200);XCTAssertFalse(g.enemies.contains{$0.detected});XCTAssertEqual(g.health,3)}
    func testVisionIsRangeLimited(){let e=Enemy(id:0,position:.zero,home:.zero,beam:V3(0,0,-1),facing:V3(0,0,-1));XCTAssertTrue(Survival.inBeam(e,V3(0,7.6,-20)));XCTAssertFalse(Survival.inBeam(e,V3(0,7.6,-29)));XCTAssertFalse(Survival.inBeam(e,V3(15,7.6,-20)))}
    func testTravelStreamsLoot(){let g=make();let old=g.supplies.map{$0.id};g.step(dt:0.1,player:V3(25,0,0),noise:0,reliable:true,cover:{_ in true},blocked:{_,_ in false});XCTAssertTrue(g.supplies.contains{!old.contains($0.id)});XCTAssertLessThanOrEqual(g.supplies.count,12)}
    func testSupplyHeightAdjustsGradually(){let g=make();let old=g.supplies[0].position;g.groundSupplies(dt:0.1,ground:{_ in -3});XCTAssertLessThan(g.supplies[0].position.y,old.y);XCTAssertEqual(g.supplies[0].position.x,old.x)}
    func testMissingGroundPreservesLoot(){let g=make();let old=g.supplies[0].position;g.groundSupplies(dt:0.1,ground:{_ in nil});XCTAssertEqual(g.supplies[0].position,old)}
    func testFullRoundCanBeWon(){let g=make();advance(g,1810);XCTAssertEqual(g.stage,.won);XCTAssertEqual(g.health,3)}
}
