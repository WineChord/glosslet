public enum LaunchAtLoginPreference {
    public static let defaultEnabled = true

    public static func resolve(storedValue: Bool?) -> Bool {
        storedValue ?? defaultEnabled
    }
}
