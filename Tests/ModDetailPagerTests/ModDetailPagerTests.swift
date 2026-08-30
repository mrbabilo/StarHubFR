import Testing
@testable import StarHubTHCore

struct ModDetailPagerTests {
    @Test func milieu() {
        let n = ModDetailPager.neighbors(of: "b", in: ["a", "b", "c"])
        #expect(n.previous == "a" && n.next == "c")
    }

    @Test func bords() {
        #expect(ModDetailPager.neighbors(of: "a", in: ["a", "b"]).previous == nil)
        #expect(ModDetailPager.neighbors(of: "b", in: ["a", "b"]).next == nil)
    }

    @Test func absentEtVide() {
        let n = ModDetailPager.neighbors(of: "x", in: ["a", "b"])
        #expect(n.previous == nil && n.next == nil)
        let v = ModDetailPager.neighbors(of: "a", in: [])
        #expect(v.previous == nil && v.next == nil)
    }

    @Test func singleton() {
        let n = ModDetailPager.neighbors(of: "a", in: ["a"])
        #expect(n.previous == nil && n.next == nil)
    }
}
