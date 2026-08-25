import XCTest
import Carbon.HIToolbox
@testable import Glance

final class HotkeyComboTests: XCTestCase {
    func test_default_isOptionShiftT() {
        let combo = HotkeyCombo.default
        XCTAssertEqual(combo.keyCode, UInt32(17)) // kVK_ANSI_T
        XCTAssertTrue(combo.carbonModifiers & UInt32(optionKey) != 0)
        XCTAssertTrue(combo.carbonModifiers & UInt32(shiftKey) != 0)
        XCTAssertEqual(combo.displayString, "⌥⇧T")
    }

    func test_displayString_modifierOrder() {
        let combo = HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_R),
            carbonModifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey)
        )
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘R")
    }

    func test_validation_rejectsShiftOnly_andBareKeys() {
        XCTAssertNil(HotkeyCombo.validatedCarbonModifiers(from: [.shift]))
        XCTAssertNil(HotkeyCombo.validatedCarbonModifiers(from: []))
        XCTAssertNotNil(HotkeyCombo.validatedCarbonModifiers(from: [.command, .shift]))
        XCTAssertNotNil(HotkeyCombo.validatedCarbonModifiers(from: [.option]))
        XCTAssertNotNil(HotkeyCombo.validatedCarbonModifiers(from: [.control]))
    }

    func test_codableRoundtrip() throws {
        let original = HotkeyCombo(keyCode: 15,
                                   carbonModifiers: UInt32(cmdKey | shiftKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
