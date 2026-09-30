import SwiftUI
import YatmoSDK

/// Functional test of the Yatmo iOS SDK: a map on a Brussels listing plus every client call,
/// each result printed and appended to Documents/yatmo-test.log so an automated run can read it.
let testLatitude = 50.8520525
let testLongitude = 4.3442926

let yatmo = Yatmo(configuration: YatmoConfiguration(
    licenseKey: yatmoTestLicenseKey, // LicenseKey.local.swift, ignored by git
    country: .BE,
    language: .FR
))

@main
struct YatmoExampleApp: App {
    var body: some Scene {
        WindowGroup {
            if CommandLine.arguments.contains("-demo") {
                DemoListingView() // marketing screenshot; add -scrolled to start on the neighbourhood section
            } else {
                ContentView()
            }
        }
    }
}

final class TestLog: ObservableObject {
    static let shared = TestLog()
    @Published var lines: [String] = []
    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("yatmo-test.log")

    func log(_ line: String) {
        print("YatmoTest: " + line)
        DispatchQueue.main.async {
            self.lines.append(line)
            try? self.lines.joined(separator: "\n").write(to: self.file, atomically: true, encoding: .utf8)
        }
    }
}
