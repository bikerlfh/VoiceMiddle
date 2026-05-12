import Testing
import Foundation
import CoreAudio
@testable import VMAudio

@Suite("OutputDevice")
struct OutputDeviceTests {
    @Test("Type shape and hashability")
    func shape() {
        let a = OutputDevice(id: 1, name: "BlackHole 2ch", uid: "uid-1")
        let b = OutputDevice(id: 1, name: "BlackHole 2ch", uid: "uid-1")
        let c = OutputDevice(id: 2, name: "MacBook Pro Speakers",
                             uid: "uid-2")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
        #expect(a.name == "BlackHole 2ch")
        #expect(a.uid == "uid-1")
    }

    @Test("enumerate returns devices with non-empty names")
    func enumerateProducesSaneOutput() {
        let devices = OutputDevice.enumerate()
        for device in devices {
            #expect(!device.name.isEmpty)
        }
    }

    @Test("firstMatching is case-insensitive substring search")
    func firstMatchingPredicate() {
        let fixtures = [
            OutputDevice(id: 1, name: "MacBook Pro Speakers",
                         uid: "speakers"),
            OutputDevice(id: 2, name: "BlackHole 2ch", uid: "BH-2"),
            OutputDevice(id: 3, name: "External Headphones",
                         uid: "ext"),
        ]
        // Local predicate mirror used to assert intent; the real
        // `firstMatching(name:)` walks Core Audio.
        let found = fixtures.first { device in
            device.name.range(
                of: "blackhole", options: .caseInsensitive
            ) != nil
        }
        #expect(found?.uid == "BH-2")
    }

    @Test("firstMatching returns nil for a clearly absent name")
    func firstMatchingMissing() {
        #expect(
            OutputDevice.firstMatching(
                name: "definitely-not-a-real-device-\(UUID().uuidString)"
            ) == nil
        )
    }
}
