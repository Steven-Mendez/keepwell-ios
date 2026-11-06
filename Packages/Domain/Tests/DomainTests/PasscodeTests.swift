import Domain
import Testing

@Suite("Passcode")
struct PasscodeTests {
    @Test(arguments: ["12345", "1234567", "12a456", "", "١٢٣٤٥٦"])
    func onlySixPlainDigitsAreAPasscode(_ digits: String) {
        #expect(throws: DomainError.invalidPasscode) { try Passcode(digits) }
    }

    @Test(arguments: ["000000", "123456", "654321", "890123", "210987"])
    func repeatedOrConsecutiveDigitsAreTooSimple(_ digits: String) throws {
        #expect(try Passcode(digits).isTooSimple)
    }

    @Test(arguments: ["482915", "112233", "135790", "120000"])
    func otherCodesAreFine(_ digits: String) throws {
        #expect(try !Passcode(digits).isTooSimple)
    }
}
