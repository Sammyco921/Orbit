import Foundation
import MachO

struct MemoryUsage {
    static var current: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let mb = Double(info.resident_size) / 1024.0 / 1024.0
            if mb > 1024 {
                return String(format: "%.1f GB", mb / 1024.0)
            }
            return String(format: "%.0f MB", mb)
        }
        return "?"
    }
}
