import simd

// Port of the GLSL ES 1.00 sources in view/TripleShotPremiumRenderer.kt (TripleShotGame dd722e5), companion
// `VERTEX` (lines 311-315) and `FRAGMENT` (lines 316-384), translated statement by statement into the Metal Shading
// Language (spec 06 sections 4.7, 8 items 5-7 and 9.4). The library is compiled at run time from this string
// (`MTLDevice.makeLibrary(source:options:)`), like the Splash precedent.
//
// The only intentional changes (marked PORT in the source):
//  - GL clip z ([-w, w]) is remapped to Metal's [0, w] in the vertex function: `z = (z + w) * 0.5`. The CPU keeps the
//    GL-convention matrices (gameplay uses them through project/screenGround) and the depth values stay identical.
//  - `exp(-pow(v, 2.0))` becomes `exp(-(v * v))`: GLSL ES leaves pow() with a negative base undefined (Adreno returns
//    v * v), MSL's pow is exp2(y * log2(x)) = NaN for v < 0. `pow(waves, 8.0)` (waves in [0, 1]) is written as squares
//    so a 1-ulp negative sine can never produce NaN either.
//  - `discard` is `discard_fragment()` followed by a dummy return (MSL needs a return value).
//  - The floor branch's court-line `marks`, `key` and `baseline` (and the `line()` helper) are computed by Android and
//    never used (dead code, spec 06 section 4.7 mode 2); they are left out.
//  - `precision mediump float` has no MSL equivalent; everything is fp32 (spec 06 section 8 item 19).
// Uniforms: GL's sticky glUniform state becomes one `TripleUniforms` value (mirrored below, same offsets) passed with
// setVertexBytes/setFragmentBytes at buffer index 1 for every draw. Vertex data: the interleaved stride-32 layout of
// TripleShotMesh (x, y, z, u, v, nx, ny, nz) through a vertex descriptor at buffer index 0.

/// The Swift mirror of the MSL `TripleUniforms` (144 bytes, same member offsets: vp 0, color 64, floorPhoto 80,
/// flex 96, hoop 104, time 112, court 116, team 120, spin 124, mode 128). GL initialises every uniform to 0 at link
/// time; so does this value.
struct TripleUniforms {
    /// uVp (column-major, the Kotlin FloatArray order).
    var vp = simd_float4x4()
    /// uColor.
    var color = SIMD4<Float>(0, 0, 0, 0)
    /// uFloorPhoto.
    var floorPhoto = SIMD4<Float>(0, 0, 0, 0)
    /// uFlex.
    var flex = SIMD2<Float>(0, 0)
    /// uHoop (x, z).
    var hoop = SIMD2<Float>(0, 0)
    /// uTime.
    var time: Float = 0
    /// uCourt.
    var court: Float = 0
    /// uTeam.
    var team: Float = 0
    /// uSpin.
    var spin: Float = 0
    /// uMode.
    var mode: Int32 = 0
    var pad0: Int32 = 0
    var pad1: Int32 = 0
    var pad2: Int32 = 0
}

enum TripleShotPremiumShaders {
    /// The vertex function (Kotlin `VERTEX`).
    static let VERTEX_FUNCTION = "tripleVertex"
    /// The fragment function (Kotlin `FRAGMENT`).
    static let FRAGMENT_FUNCTION = "tripleFragment"

    /// Both shaders, as one MSL library source.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // attribute vec3 aPosition; attribute vec2 aUv; attribute vec3 aNormal;
    struct TripleVertexIn {
        float3 position [[attribute(0)]];
        float2 uv [[attribute(1)]];
        float3 normal [[attribute(2)]];
    };

    // uniform mat4 uVp; uniform vec2 uFlex; uniform vec4 uColor; uniform int uMode; uniform float uTime;
    // uniform float uCourt; uniform float uTeam; uniform vec2 uHoop; uniform float uSpin; uniform vec4 uFloorPhoto;
    struct TripleUniforms {
        float4x4 vp;
        float4 color;
        float4 floorPhoto;
        float2 flex;
        float2 hoop;
        float time;
        float court;
        float team;
        float spin;
        int mode;
        int pad0;
        int pad1;
        int pad2;
    };

    // varying vec2 vUv; varying vec3 vWorld; varying vec3 vNormal;
    struct TripleVaryings {
        float4 position [[position]];
        float2 uv;
        float3 world;
        float3 normal;
    };

    vertex TripleVaryings tripleVertex(TripleVertexIn in [[stage_in]],
                                       constant TripleUniforms &u [[buffer(1)]]) {
        TripleVaryings o;
        o.uv = in.uv;
        o.world = in.position;
        o.normal = in.normal;
        float3 p = in.position;
        float w = clamp((3.35f - p.y) / 0.75f, 0.0f, 1.0f);
        p.x += u.flex.x + u.flex.y * w * w;
        p.z += u.flex.y * 0.35f * w;
        float4 clip = u.vp * float4(p, 1.0f);
        clip.z = (clip.z + clip.w) * 0.5f; // PORT: GL clip z [-w, w] -> Metal [0, w]
        o.position = clip;
        return o;
    }

    fragment float4 tripleFragment(TripleVaryings in [[stage_in]],
                                   constant TripleUniforms &u [[buffer(1)]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler smp [[sampler(0)]]) {
        if (u.mode == 8) {
            float3 sky = tex.sample(smp, float2(0.50f, 0.025f)).rgb;
            float3 upper = mix(sky * 0.65f, float3(0.07f, 0.075f, 0.16f), 0.35f);
            return float4(mix(upper, sky, clamp(in.uv.y, 0.0f, 1.0f)), 1.0f);
        }
        if (u.mode == 9) {
            float2 uv = in.uv;
            if (u.court > 0.5f) uv.x = 0.63f * (1.0f - abs(fract(in.uv.x * 2.5f + 0.19f) * 2.0f - 1.0f));
            float4 c = tex.sample(smp, uv);
            float bottom = u.court > 0.5f ? 0.56f : 0.18f;
            float fade = smoothstep(0.0f, 0.07f, in.uv.x) * (1.0f - smoothstep(0.93f, 1.0f, in.uv.x))
                * smoothstep(0.0f, 0.025f, in.uv.y) * (1.0f - smoothstep(bottom - 0.035f, bottom, in.uv.y));
            return float4(c.rgb * fade, c.a * fade);
        }
        if (u.mode == 1 || u.mode == 5) {
            float2 uv = in.uv;
            if (u.mode == 5) {
                float2 q = in.uv - 0.5f;
                // GLSL mat2(cos, -sin, sin, cos) is column-major: columns (cos, -sin) and (sin, cos).
                uv = float2x2(float2(cos(u.spin), -sin(u.spin)), float2(sin(u.spin), cos(u.spin))) * q + 0.5f;
                if (any(uv < float2(0.0f)) || any(uv > float2(1.0f))) {
                    discard_fragment(); // PORT: discard
                    return float4(0.0f);
                }
            }
            float4 c = tex.sample(smp, uv);
            if (c.a < 0.16f) {
                discard_fragment(); // PORT: discard
                return float4(0.0f);
            }
            float light = 1.0f;
            if (u.mode == 5) {
                float2 p = (in.uv - 0.5f) * 2.0f;
                light = 0.69f + 0.39f * sqrt(max(0.0f, 1.0f - dot(p, p))) - 0.10f * p.x;
            }
            return float4(c.rgb * u.color.rgb * light * u.color.a, c.a * u.color.a);
        }
        if (u.mode == 3 || u.mode == 4) {
            float2 p = (in.uv - 0.5f) * 2.0f;
            float r = dot(p, p);
            float alpha = u.mode == 3 ? (1.0f - smoothstep(0.05f, 1.0f, r))
                : smoothstep(0.68f, 0.79f, r) * (1.0f - smoothstep(0.86f, 1.0f, r));
            return float4(u.color.rgb * u.color.a * alpha, u.color.a * alpha);
        }
        if (u.mode == 6) {
            return u.color;
        }
        if (u.mode == 7) {
            float2 p = in.world.xz;
            float waves = sin(p.y * 10.0f + sin(p.x * 0.8f + u.time * 0.4f) * 2.0f - u.time * 0.9f) * 0.5f + 0.5f;
            float broad = sin(p.y * 0.6f + u.time * 0.15f) * 0.5f + 0.5f;
            float3 water = mix(float3(0.095f, 0.12f, 0.21f), float3(0.21f, 0.19f, 0.28f), broad);
            float s = (p.x - u.hoop.x - 5.0f) * 0.13f;
            float sunset = exp(-(s * s)); // PORT: exp(-pow(s, 2.0))
            float waves2 = waves * waves;
            float waves4 = waves2 * waves2;
            water += float3(0.30f, 0.12f, 0.05f) * sunset * (0.25f + 0.75f * (waves4 * waves4)); // PORT: pow(waves, 8.0)
            if (u.court > 0.5f) {
                float grass = sin(p.x * 13.7f + sin(p.y * 3.1f)) * sin(p.y * 17.3f + p.x * 2.7f);
                float patches = sin(p.x * 0.71f) * sin(p.y * 0.53f);
                water = float3(0.075f, 0.16f, 0.095f) + float3(0.018f, 0.027f, 0.009f) * grass
                    + float3(0.025f, 0.036f, 0.013f) * patches;
            }
            return float4(water, 1.0f);
        }
        if (u.mode == 2) {
            float2 p = in.world.xz;
            float grain = sin(p.x * 157.0f + p.y * 73.0f) * sin(p.y * 197.0f - p.x * 51.0f);
            float center = u.team > 0.5f ? 0.0f : u.hoop.x;
            // Reproject the photograph's unobstructed far half onto the flat floor.
            // Homogeneous UVs undo its baked perspective; the GPU camera supplies the new perspective.
            // Mirror that half for a full court, avoiding the baked near backboard entirely.
            float t = u.team > 0.5f ? 1.0f - abs(p.y) / 10.8f : (p.y - u.hoop.y + 1.5f) / 12.3f;
            t = clamp(t, 0.0f, 1.0f);
            float ratio = u.floorPhoto.x / u.floorPhoto.y;
            float denominator = 1.0f + (ratio - 1.0f) * t;
            float2 uv = float2(0.5f + (p.x - center) / 16.0f * u.floorPhoto.x / denominator,
                (u.floorPhoto.z + (u.floorPhoto.w * ratio - u.floorPhoto.z) * t) / denominator);
            float3 art = tex.sample(smp, uv).rgb;
            float3 c = art * 0.94f + grain * 0.003f;
            float cyan = exp(-abs(p.x - center + 7.7f) * 0.90f);
            float magenta = exp(-abs(p.x - center - 7.7f) * 0.90f);
            c += float3(0.03f, 0.20f, 0.28f) * cyan + float3(0.23f, 0.015f, 0.18f) * magenta;
            // PORT: Android computes `key`, `baseline` and the court-line `marks` here and never uses them.
            if (u.court > 0.5f) {
                float3 forestArt = tex.sample(smp, float2(in.uv.x, 0.70f + in.uv.y * 0.29f)).rgb;
                c = forestArt * 0.98f;
            }
            float sx = p.x * 0.28f;
            float sz = (p.y + 7.0f) * 0.10f;
            float shine = exp(-(sx * sx) - (sz * sz)); // PORT: exp(-pow(sx, 2.0) - pow(sz, 2.0))
            c += float3(0.18f, 0.105f, 0.045f) * shine;
            return float4(c, 1.0f);
        }
        float light = 0.65f + 0.35f * max(0.0f, dot(normalize(in.normal), normalize(float3(-0.45f, 0.8f, 0.5f))));
        return float4(u.color.rgb * light * u.color.a, u.color.a);
    }
    """
}
