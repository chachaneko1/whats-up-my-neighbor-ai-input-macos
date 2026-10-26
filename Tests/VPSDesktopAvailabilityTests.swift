import Foundation

@main
enum VPSDesktopAvailabilityTests {
    static func main() {
        precondition(VPSDesktopAvailability.declaresHost("Host neighbor-vps\n  HostName 203.0.113.10\n"))
        precondition(VPSDesktopAvailability.declaresHost("Host github.com neighbor-vps\n"), "One line may list several hosts")
        precondition(VPSDesktopAvailability.declaresHost("  host=neighbor-vps\n"), "Keyword is case-insensitive and may use =")
        precondition(VPSDesktopAvailability.declaresHost("Host \"neighbor-vps\" # office\n"))
        precondition(!VPSDesktopAvailability.declaresHost(""), "No SSH config means gray")
        precondition(!VPSDesktopAvailability.declaresHost("Host other\n  HostName neighbor-vps\n"), "HostName is not an alias")
        precondition(!VPSDesktopAvailability.declaresHost("# Host neighbor-vps\n"), "Commented out")
        precondition(!VPSDesktopAvailability.declaresHost("Host neighbor-*\nHost *\n"), "Wildcards do not count")
        precondition(!VPSDesktopAvailability.declaresHost("Host !neighbor-vps\n"), "Negation does not count")
        precondition(!VPSDesktopAvailability.declaresHost("Host neighbor-vps-old\n"))

        precondition(VPSDesktopAvailability.nodePath(isExecutable: { _ in false }) == nil, "Missing Node.js means gray")
        precondition(VPSDesktopAvailability.nodePath(isExecutable: { $0 == "/usr/local/bin/node" }) == "/usr/local/bin/node")
        precondition(VPSDesktopAvailability.nodePath(isExecutable: { _ in true }) == "/opt/homebrew/opt/node@24/bin/node",
                     "Prefer the Node.js the Preview was verified with")
        print("VPS desktop availability tests passed.")
    }
}
