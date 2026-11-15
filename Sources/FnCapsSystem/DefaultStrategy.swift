public enum DefaultStrategy {
    /// 2026-10-24 confirmed in 01-12 (FINDINGS E7, user decision "confirm"): S7-NativeHop keeps composition in the
    /// regression bench (100%, delay 0) and in real apps. Known limits: ~70-80 ms when not composing, double indicator flash.
    public static let name: String = "S7-NativeHop"
}
