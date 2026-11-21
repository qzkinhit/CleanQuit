import Foundation

struct MountedDiskImage: Identifiable, Equatable, Hashable {
    let deviceEntry: String
    let mountPoint: String
    let imagePath: String

    var id: String { deviceEntry }

    var displayName: String {
        URL(fileURLWithPath: mountPoint).lastPathComponent
    }
}

final class DiskImageCleanerService {
    func findIdleMountedDiskImages(activeExecutablePaths: [String]) -> [MountedDiskImage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return Self.parseIdleImages(fromPlistData: data, activeExecutablePaths: activeExecutablePaths)
        } catch {
            return []
        }
    }

    func ejectDiskImages(_ images: [MountedDiskImage]) -> Int {
        var ejectedCount = 0
        for image in images {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", image.deviceEntry, "-quiet"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    ejectedCount += 1
                }
            } catch {
                continue
            }
        }
        return ejectedCount
    }

    static func parseIdleImages(
        fromPlistData data: Data,
        activeExecutablePaths: [String]
    ) -> [MountedDiskImage] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return []
        }

        var results: [MountedDiskImage] = []
        for entry in images {
            guard let imagePath = entry["image-path"] as? String else { continue }
            let lowerImage = imagePath.lowercased()
            guard lowerImage.hasSuffix(".dmg") || lowerImage.hasSuffix(".iso") else { continue }
            guard let entities = entry["system-entities"] as? [[String: Any]] else { continue }

            let rootDev = entities.compactMap { $0["dev-entry"] as? String }.sorted().first
            for entity in entities {
                guard let mountPoint = entity["mount-point"] as? String,
                      mountPoint.hasPrefix("/Volumes/") else {
                    continue
                }
                let inUse = activeExecutablePaths.contains { $0.hasPrefix(mountPoint + "/") }
                guard !inUse else { continue }

                let devEntry = rootDev ?? (entity["dev-entry"] as? String ?? mountPoint)
                results.append(
                    MountedDiskImage(
                        deviceEntry: devEntry,
                        mountPoint: mountPoint,
                        imagePath: imagePath
                    )
                )
                break
            }
        }

        return results
    }
}
