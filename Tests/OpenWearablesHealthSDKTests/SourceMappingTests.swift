import HealthKit
import XCTest
@testable import OpenWearablesHealthSDK

/// What `_mapSource` claims about hardware, and what it must not claim.
///
/// The payload carries two different assertions that used to share one field: the unit
/// that recorded a sample, and the hardware that ran the app which wrote it. For a
/// first-party sample they are the same object. For anything relayed through the phone
/// they are not, and collapsing them told the backend that a chest strap was an iPhone.
final class SourceMappingTests: XCTestCase {
    private func revision(productType: String?) -> HKSourceRevision {
        return HKSourceRevision(
            source: HKSource.default(),
            version: "1.0",
            productType: productType,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
        )
    }

    private func device(
        name: String?,
        model: String?,
        localIdentifier: String? = nil,
        udi: String? = nil
    ) -> HKDevice {
        return HKDevice(
            name: name,
            manufacturer: "Polar Electro Oy",
            model: model,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: "5.1.3",
            localIdentifier: localIdentifier,
            udiDeviceIdentifier: udi
        )
    }

    func testRecorderAndHostAreSeparateFields() {
        let mapped = OpenWearablesHealthSDK.shared._mapSource(
            revision(productType: "iPhone18,1"),
            device: device(name: "Polar H10 C0FF33", model: "H10")
        )

        // The strap, not the handset it synced through.
        XCTAssertEqual(mapped["deviceModel"] as? String, "H10")
        XCTAssertEqual(mapped["productType"] as? String, "iPhone18,1")
    }

    func testDeviceIdentifierIsSent() {
        let mapped = OpenWearablesHealthSDK.shared._mapSource(
            revision(productType: "Watch7,12"),
            device: device(name: "Apple Watch", model: "Watch", localIdentifier: "ABC-123")
        )
        XCTAssertEqual(mapped["deviceId"] as? String, "ABC-123")
    }

    func testDeviceIdentifierFallsBackToUDI() {
        let mapped = OpenWearablesHealthSDK.shared._mapSource(
            revision(productType: nil),
            device: device(name: "Polar H10", model: "H10", localIdentifier: nil, udi: "UDI-999")
        )
        XCTAssertEqual(mapped["deviceId"] as? String, "UDI-999")
    }

    /// A device that exists but names nothing must serialize as JSON null. The previous
    /// `device?.name as Any? ?? NSNull()` left a wrapped nil in the dictionary here,
    /// which JSONSerialization rejects - taking the whole upload with it.
    func testPresentDeviceWithEmptyFieldsSerializes() {
        let mapped = OpenWearablesHealthSDK.shared._mapSource(
            revision(productType: "iPhone18,1"),
            device: device(name: nil, model: nil)
        )

        XCTAssertTrue(mapped["deviceModel"] is NSNull)
        XCTAssertTrue(mapped["deviceName"] is NSNull)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(mapped))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: mapped))
    }

    func testNoDeviceLeavesRecorderFieldsNull() {
        let mapped = OpenWearablesHealthSDK.shared._mapSource(revision(productType: "iPhone18,1"), device: nil)

        XCTAssertTrue(mapped["deviceId"] is NSNull)
        XCTAssertTrue(mapped["deviceModel"] is NSNull)
        XCTAssertEqual(mapped["productType"] as? String, "iPhone18,1")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(mapped))
    }

    // MARK: - Device type

    /// The case that motivated the change: the recorder decides the type, not the host.
    func testTypeComesFromTheRecorderNotTheHost() {
        let sdk = OpenWearablesHealthSDK.shared

        XCTAssertEqual(
            sdk._inferDeviceType(productType: "iPhone18,1", device: device(name: "Polar H10", model: "H10")) as? String,
            "chest_strap"
        )
        XCTAssertEqual(
            sdk._inferDeviceType(productType: "iPhone18,1", device: device(name: "Michael's AirPods Pro", model: nil)) as? String,
            "head_mounted"
        )
        XCTAssertEqual(
            sdk._inferDeviceType(productType: "iPhone18,1", device: device(name: "Muse S", model: nil)) as? String,
            "head_mounted"
        )
    }

    /// With no device record the productType is the only hardware string there is, and
    /// for a first-party sample it genuinely names the recorder.
    func testHostIsUsedOnlyWhenNoDeviceIsReported() {
        let sdk = OpenWearablesHealthSDK.shared

        XCTAssertEqual(sdk._inferDeviceType(productType: "Watch7,12", device: nil) as? String, "watch")
        XCTAssertEqual(sdk._inferDeviceType(productType: "iPhone18,1", device: nil) as? String, "phone")
    }

    /// A device that names nothing recognisable yields no type at all. Falling through to
    /// the host would report "phone" for hardware we simply failed to recognise, and a
    /// confident wrong answer outranks the backend's own inference.
    func testUnrecognisedDeviceYieldsNoTypeRatherThanTheHosts() {
        let mapped = OpenWearablesHealthSDK.shared._inferDeviceType(
            productType: "iPhone18,1",
            device: device(name: "Bluetooth Device", model: nil)
        )
        XCTAssertTrue(mapped is NSNull)
    }

    func testNothingReportedYieldsNoType() {
        XCTAssertTrue(OpenWearablesHealthSDK.shared._inferDeviceType(productType: nil, device: nil) is NSNull)
    }
}
