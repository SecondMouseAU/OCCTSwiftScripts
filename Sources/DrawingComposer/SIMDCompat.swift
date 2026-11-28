// SIMDCompat.swift: the Apple `simd` functions DrawingComposer calls, for a build where Apple's
// `simd` module does not exist (WASI). OCCTSwift stopped shipping a WASI-only `simd` shim in
// 4.0.0, and defines no `simd_*` function now (OCCTSwift#3291), so each is written here over the
// standard library's own SIMD types, which are the same on every platform. Apple builds import the
// real module and compile none of this.

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
    func simd_min<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable {
        pointwiseMin(a, b)
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    func simd_max<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable {
        pointwiseMax(a, b)
    }
#endif
