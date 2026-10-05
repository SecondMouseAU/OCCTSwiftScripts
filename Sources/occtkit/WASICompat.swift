// WASICompat.swift: the one simd matrix type occtkit needs that OCCTSwift's WASI-only `simd` shim
// (Sources/WASICompat/simd in OCCTSwift) does not provide. Mirrors the Apple `simd_double4x4`
// surface Transform.swift uses: identity from a scalar, diagonal, column initializer, `columns`,
// and the matrix product.

#if os(WASI)
    import simd

    // swift-format-ignore: TypeNamesShouldBeCapitalized
    struct simd_double4x4 {
        var columns: (SIMD4<Double>, SIMD4<Double>, SIMD4<Double>, SIMD4<Double>)

        init(_ c0: SIMD4<Double>, _ c1: SIMD4<Double>, _ c2: SIMD4<Double>, _ c3: SIMD4<Double>) {
            columns = (c0, c1, c2, c3)
        }

        /// `scalar` on the diagonal, as `simd_double4x4(1.0)` is the identity.
        init(_ scalar: Double) {
            self.init(diagonal: SIMD4(scalar, scalar, scalar, scalar))
        }

        init(diagonal d: SIMD4<Double>) {
            self.init(
                SIMD4(d.x, 0, 0, 0), SIMD4(0, d.y, 0, 0), SIMD4(0, 0, d.z, 0), SIMD4(0, 0, 0, d.w))
        }

        static func * (a: simd_double4x4, b: simd_double4x4) -> simd_double4x4 {
            func apply(_ v: SIMD4<Double>) -> SIMD4<Double> {
                a.columns.0 * v.x + a.columns.1 * v.y + a.columns.2 * v.z + a.columns.3 * v.w
            }
            return simd_double4x4(
                apply(b.columns.0), apply(b.columns.1), apply(b.columns.2), apply(b.columns.3))
        }
    }
#endif
