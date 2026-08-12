import Foundation
import XCTest

/// Ensures sample / feature harness sources never import OS clipboard kits.
/// Feature harness may import TaqlynSDK + TaqlynNavSwiftUI (not UIPasteboard / UIKit pasteboard).
final class SampleSourceGuardTests: XCTestCase {
    func testSampleSources_doNotReferenceUIPasteboard() throws {
        let sampleRoot = try locateSampleRoot()
        XCTAssertTrue(sampleRoot.isDirectory)

        let files = try walkSwiftSources(under: sampleRoot)
        XCTAssertFalse(files.isEmpty, "expected sample Swift sources under \(sampleRoot.path)")

        let forbidden = ["UIPasteboard", "UIKit.UIPasteboard"]
        var offenders: [String] = []

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in forbidden {
                if text.contains(needle) {
                    offenders.append("\(file.path) contains \(needle)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, offenders.joined(separator: "\n"))
    }

    private func locateSampleRoot() throws -> URL {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("Samples/TaqlynSample"),
            cwd.appendingPathComponent("../Samples/TaqlynSample"),
            cwd.appendingPathComponent("packages/sdk-ios/Samples/TaqlynSample"),
        ]
        if let hit = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return hit
        }
        throw XCTSkip("Samples/TaqlynSample not found from \(cwd.path)")
    }

    private func walkSwiftSources(under root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "swift" {
                results.append(url)
            }
        }
        return results
    }
}

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
