/// Deterministic RNG (SplitMix64) so selection and shuffling are reproducible in tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Type-erased RNG so value types can hold "some RNG" without generics leaking everywhere.
public struct AnyRandomGenerator: RandomNumberGenerator, Sendable {
    private var base: SeededGenerator

    /// Seeded (deterministic) generator.
    public init(seed: UInt64) { base = SeededGenerator(seed: seed) }

    /// Seeded from the system RNG.
    public static func system() -> AnyRandomGenerator {
        var sys = SystemRandomNumberGenerator()
        return AnyRandomGenerator(seed: sys.next())
    }

    public mutating func next() -> UInt64 { base.next() }
}
