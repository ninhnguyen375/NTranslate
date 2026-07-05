import Foundation

struct APIKeychain {
    static func load(service: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NSError(domain: "Keychain", code: Int(task.terminationStatus)) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw NSError(domain: "Keychain", code: 1)
        }
        return value
    }
}
