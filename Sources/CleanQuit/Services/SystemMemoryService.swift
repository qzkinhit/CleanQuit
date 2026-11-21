import Darwin
import Foundation

enum MemoryPressureLevel: String, Codable, Equatable {
    case normal
    case elevated
    case critical

    var label: String {
        switch self {
        case .normal:
            return "内存充裕"
        case .elevated:
            return "负载偏高"
        case .critical:
            return "内存高压"
        }
    }
}

struct SystemMemorySnapshot: Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let appMemoryBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(usedBytes) / Double(totalBytes))
    }

    var pressureLevel: MemoryPressureLevel {
        guard totalBytes > 0 else { return .normal }
        let compressedRatio = Double(compressedBytes) / Double(totalBytes)
        let gigabyte: UInt64 = 1_073_741_824

        if swapUsedBytes >= 3 * gigabyte || compressedRatio >= 0.30 || usageRatio >= 0.90 {
            return .critical
        }
        if swapUsedBytes >= 512 * 1_048_576 || compressedRatio >= 0.16 || usageRatio >= 0.78 {
            return .elevated
        }
        return .normal
    }
}

enum MemoryFormatter {
    static func string(fromBytes bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        if mb >= 10.0 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f MB", max(0.1, mb))
    }
}

final class SystemMemoryService {
    func captureSnapshot() -> SystemMemorySnapshot {
        var totalMem: UInt64 = 0
        var memSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &memSize, nil, 0)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var pageSize: vm_size_t = 16384
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)

        guard kr == KERN_SUCCESS else {
            return SystemMemorySnapshot(
                totalBytes: totalMem,
                usedBytes: 0,
                appMemoryBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                swapUsedBytes: swap.xsu_used,
                swapTotalBytes: swap.xsu_total
            )
        }

        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        let appPages = internalPages > purgeablePages ? (internalPages - purgeablePages) : internalPages
        let appMemoryBytes = appPages * pageBytes
        let wiredBytes = UInt64(vmStats.wire_count) * pageBytes
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageBytes
        let usedBytes = min(totalMem, appMemoryBytes + wiredBytes + compressedBytes)

        return SystemMemorySnapshot(
            totalBytes: totalMem,
            usedBytes: usedBytes,
            appMemoryBytes: appMemoryBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            swapUsedBytes: swap.xsu_used,
            swapTotalBytes: swap.xsu_total
        )
    }
}
