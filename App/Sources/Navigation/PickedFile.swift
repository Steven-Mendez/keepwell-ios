import Foundation

/// A file the person picked lives outside the sandbox, readable only inside its security scope.
enum PickedFile {
    static func data(at url: URL) -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? Data(contentsOf: url)
    }
}
