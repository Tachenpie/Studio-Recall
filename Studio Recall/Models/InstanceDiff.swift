struct InstanceDiff {
    let instanceID: UUID
    let deviceName: String
    let location: String   // "Rack 1 Slot 3" or "Chassis A Slot 2"
    let diffs: [ControlDiff]
}
