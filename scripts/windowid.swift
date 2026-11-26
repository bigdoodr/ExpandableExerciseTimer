import CoreGraphics
import Foundation

// Prints the CGWindowID of the largest on-screen window owned by the given pid, for `screencapture -l`.
guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: windowid.swift <pid>\n".utf8)); exit(2)
}
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
func area(_ w: [String: Any]) -> Double {
    guard let b = w[kCGWindowBounds as String] as? [String: Double] else { return 0 }
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
guard let best = owned.max(by: { area($0) < area($1) }), let id = best[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write(Data("no window for pid \(pid)\n".utf8)); exit(1)
}
print(id)
