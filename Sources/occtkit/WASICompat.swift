// WASICompat.swift: the Apple `simd` surface occtkit calls, for a build where Apple's `simd` module
// does not exist (WASI). OCCTSwift stopped shipping a WASI-only `simd` shim in 4.0.0 and defines no
// `simd_*` function now (OCCTSwift#3291), so the vector functions are written here over the
// standard library's own SIMD types, and the one matrix type is mirrored: the `simd_double4x4`
// surface Transform.swift uses (identity from a scalar, diagonal, column initializer, `columns`,
// and the matrix product). Apple builds import the real module and compile none of this.

#if !canImport(simd)
    // swift-format-ignore: AlwaysUseLowerCamelCase
    func simd_length<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint {
        (v * v).sum().squareRoot()
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    func simd_normalize<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint {
        v / simd_length(v)
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    func simd_dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint {
        (a * b).sum()
    }

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
