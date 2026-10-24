import XCTest
@testable import MinikTripleShot

// Parity tests for area s-home (spec 18): TripleShotDemoActivity.kt, ui/TripleShotHostFragment.kt,
// ui/TripleShotHomeFragment.kt and the layouts activity_triple_shot_demo.xml, fragment_triple_shot_host.xml,
// fragment_triple_shot_home.xml.
//
// - Ball and characters: golden vectors from a JVM oracle that runs the Kotlin statements of installAndStartHomeBall
//   (L393-480, the frame body verbatim, the clock replaced by a fixed 60 Hz schedule: frame k at
//   180 ms + k * 16 666 667 ns, install at 0) and placeCharacters (L337-379) in Kotlin Float maths
//   (scratch work/s-home/harness/src/harness/HomeGolden.kt). Values are Float bit patterns (exact parity).
//   Pixel 6 = 1080 x 1920 px at 2.625; iPhone 15 = 1179 x 2556 px at 3; iPad 13" = 2048 x 2732 px at 2.
// - The topic button text follows the app's string tables (both languages pass).
// - The layout tests check the XML ids, child order, params and the attributes the code relies on, read the way the
//   Android inflater reads them (getDimensionPixelSize / getDimension).

final class HomeTests: XCTestCase {

    private func f(_ bits: UInt32) -> Float { return Float(bitPattern: bits) }

    // MARK: - Ball (Kotlin L409-475)

    private struct BallFrame {
        let k: Int
        let x: UInt32
        let y: UInt32
        let vx: UInt32
        let vy: UInt32
        let rotation: UInt32
        let bounces: Int
        let maya: UInt32
        let again: Bool
    }

    private struct BallCase {
        let label: String
        let width: Int
        let height: Int
        let density: Float
        let size: Int
        let floorY: UInt32
        let maxX: UInt32
        let x0: UInt32
        let y0: UInt32
        let vx0: UInt32
        let frames: [BallFrame]
    }

    private let ballCases: [BallCase] = [
        BallCase(label: "pixel6", width: 1080, height: 1920, density: 2.625, size: 142,
                 floorY: 0x44DE4000, maxX: 0x446A8000, x0: 0x443B7333, y0: 0xC3234CCD, vx0: 0xC3574000, frames: [
                    BallFrame(k: 0, x: 0x4439BA5E, y: 0xC31CFBB3, vx: 0xC3574000, vy: 0x43456667, rotation: 0xC188BEF4,
                              bounces: 0, maya: 0x3F791687, again: true),
                    BallFrame(k: 15, x: 0x442C4658, y: 0x42C3FBD1, vx: 0xC3574000, vy: 0x44D972CD, rotation: 0xC2638965,
                              bounces: 0, maya: 0x3F6F7CEE, again: true),
                    BallFrame(k: 46, x: 0x441078B2, y: 0x44DE4000, vx: 0xC34607AE, vy: 0xC54B3AC0, rotation: 0xC30AE80D,
                              bounces: 1, maya: 0x3F5BA5E3, again: true),
                    BallFrame(k: 109, x: 0x43B8FA2E, y: 0x44DE4000, vx: 0xC3363007, vy: 0xC4F3EDFD, rotation: 0xC3923B4E,
                              bounces: 2, maya: 0x3F3353F8, again: true),
                    BallFrame(k: 146, x: 0x4380CD77, y: 0x44DE4000, vx: 0xC3279CD3, vy: 0xC47EBC6B, rotation: 0xC3BBADE9,
                              bounces: 3, maya: 0x3F1BA5E3, again: true),
                    BallFrame(k: 165, x: 0x434C871C, y: 0x44DE4000, vx: 0xC31A341E, vy: 0xC3E74984, rotation: 0xC3CF3867,
                              bounces: 4, maya: 0x3F0F7CED, again: true),
                    BallFrame(k: 180, x: 0x432F2D8D, y: 0x44DE4000, vx: 0xC1FC2BCB, vy: 0x00000000, rotation: 0xC3D950C7,
                              bounces: 4, maya: 0x3F05E354, again: true),
                    BallFrame(k: 290, x: 0x432C4266, y: 0x44DE4000, vx: 0xB2331F33, vy: 0x00000000, rotation: 0xC3DA334C,
                              bounces: 4, maya: 0x3E800000, again: false),
                 ]),
        BallCase(label: "iphone15", width: 1179, height: 2556, density: 3, size: 162,
                 floorY: 0x4515A000, maxX: 0x447E4000, x0: 0x444BC28F, y0: 0xC33A4CCD, vx0: 0xC3760000, frames: [
                    BallFrame(k: 0, x: 0x4449CAC0, y: 0xC33314AF, vx: 0xC3760000, vy: 0x4361999A, rotation: 0xC188D15A,
                              bounces: 0, maya: 0x3F791687, again: true),
                    BallFrame(k: 49, x: 0x4417913A, y: 0x4515A000, vx: 0xC36251EC, vy: 0xC576CD8A, rotation: 0xC3131A49,
                              bounces: 1, maya: 0x3F59BA5E, again: true),
                    BallFrame(k: 116, x: 0x43B0C5D9, y: 0x4515A000, vx: 0xC35036E4, vy: 0xC5145CF9, rotation: 0xC39B5AD5,
                              bounces: 2, maya: 0x3F2ED916, again: true),
                    BallFrame(k: 187, x: 0x42ECA320, y: 0x4515A000, vx: 0xC3222252, vy: 0xC3811DCA, rotation: 0xC3E7564C,
                              bounces: 5, maya: 0x3F016872, again: true),
                    BallFrame(k: 195, x: 0x42C987C6, y: 0x4515A000, vx: 0xC270702F, vy: 0x00000000, rotation: 0xC3EC7981,
                              bounces: 5, maya: 0x3EF89374, again: true),
                    BallFrame(k: 290, x: 0x42BE6626, y: 0x4515A000, vx: 0xB4D17932, vy: 0x00000000, rotation: 0xC3EDF41C,
                              bounces: 5, maya: 0x3E800000, again: false),
                 ]),
        BallCase(label: "ipad13", width: 2048, height: 2732, density: 2, size: 108,
                 floorY: 0x45240000, maxX: 0x44F28000, x0: 0x44BBCF5C, y0: 0xC2F86666, vx0: 0xC3240000, frames: [
                    BallFrame(k: 0, x: 0x44BB276C, y: 0xC2EEC63F, vx: 0xC3240000, vy: 0x43166667, rotation: 0xC188D15A,
                              bounces: 0, maya: 0x3F791687, again: true),
                    BallFrame(k: 63, x: 0x44A5A123, y: 0x45240000, vx: 0xC316E148, vy: 0xC551C5D5, rotation: 0xC3384E71,
                              bounces: 1, maya: 0x3F50C49C, again: true),
                    BallFrame(k: 240, x: 0x4463101C, y: 0x45240000, vx: 0xC2D82DC3, vy: 0xC3519DDA, rotation: 0xC41334A0,
                              bounces: 5, maya: 0x3EBEF9DC, again: true),
                    BallFrame(k: 290, x: 0x445EC274, y: 0x45240000, vx: 0xBC40265D, vy: 0x00000000, rotation: 0xC416F398,
                              bounces: 5, maya: 0x3E800000, again: false),
                 ]),
        // A root smaller than the ball: floorY and maxX clamp to 0 (wall bounce on the first frame).
        BallCase(label: "tiny", width: 40, height: 30, density: 1, size: 54,
                 floorY: 0x00000000, maxX: 0x00000000, x0: 0x00000000, y0: 0xC2786666, vx0: 0xC2A40000, frames: [
                    BallFrame(k: 0, x: 0x00000000, y: 0xC26EC63F, vx: 0x426C28F6, vy: 0x42966667, rotation: 0xC10538EF,
                              bounces: 0, maya: 0x3F791687, again: true),
                    BallFrame(k: 12, x: 0x00000000, y: 0x00000000, vx: 0x3F86F022, vy: 0xC3B3EA7E, rotation: 0xC111D60A,
                              bounces: 1, maya: 0x3F716873, again: true),
                    BallFrame(k: 290, x: 0x00000000, y: 0x00000000, vx: 0x00000002, vy: 0x00000000, rotation: 0xC11210A5,
                              bounces: 3, maya: 0x3E800000, again: false),
                 ]),
    ]

    func testBallMotionMatchesTheJvmGoldenVectors() {
        for c in ballCases {
            var motion = TripleShotHomeBallMotion(
                rootWidth: c.width, rootHeight: c.height, size: c.size, density: c.density, nowNs: 0
            )
            XCTAssertEqual(motion.floorY.bitPattern, c.floorY, "\(c.label) floorY")
            XCTAssertEqual(motion.maxX.bitPattern, c.maxX, "\(c.label) maxX")
            XCTAssertEqual(motion.x.bitPattern, c.x0, "\(c.label) x0")
            XCTAssertEqual(motion.y.bitPattern, c.y0, "\(c.label) y0")
            XCTAssertEqual(motion.vx.bitPattern, c.vx0, "\(c.label) vx0")
            XCTAssertEqual(motion.vy, 0)
            XCTAssertEqual(motion.bounceCount, 0)

            // `ball.rotation = -12f`, then `ball.rotation += (vx * dt / size) * 105f` every frame.
            var rotation: Float = -12
            var expected = c.frames.makeIterator()
            var next = expected.next()
            var frames = 0
            var k = 0
            while true {
                let now = Int64(180_000_000) + Int64(k) * 16_666_667
                let step = motion.frame(now: now)
                frames += 1
                if let delta = step.rotationDelta { rotation += delta }
                XCTAssertEqual(step.x.bitPattern, motion.x.bitPattern)
                XCTAssertEqual(step.y.bitPattern, motion.y.bitPattern)
                if let golden = next, golden.k == k {
                    XCTAssertEqual(step.x.bitPattern, golden.x, "\(c.label) x at frame \(k)")
                    XCTAssertEqual(step.y.bitPattern, golden.y, "\(c.label) y at frame \(k)")
                    XCTAssertEqual(motion.vx.bitPattern, golden.vx, "\(c.label) vx at frame \(k)")
                    XCTAssertEqual(motion.vy.bitPattern, golden.vy, "\(c.label) vy at frame \(k)")
                    XCTAssertEqual(rotation.bitPattern, golden.rotation, "\(c.label) rotation at frame \(k)")
                    XCTAssertEqual(motion.bounceCount, golden.bounces, "\(c.label) bounces at frame \(k)")
                    XCTAssertEqual(step.mayaAlpha.bitPattern, golden.maya, "\(c.label) Maya alpha at frame \(k)")
                    XCTAssertEqual(step.postAgain, golden.again, "\(c.label) postAgain at frame \(k)")
                    next = expected.next()
                }
                if !step.postAgain || k > 1000 { break }
                k += 1
            }
            XCTAssertNil(next, "\(c.label): every golden frame was reached")
            XCTAssertEqual(frames, 291, "\(c.label): the loop ends at 5 s (frame 290 of the 60 Hz schedule)")
        }
    }

    func testBallFirstStepIsClampedAndMayaFadesLinearly() {
        // The first frame comes 180 ms after the install: dt clamps to 0.032 s and elapsed includes the delay.
        var motion = TripleShotHomeBallMotion(rootWidth: 1080, rootHeight: 1920, size: 142, density: 2.625, nowNs: 0)
        let first = motion.frame(now: 180_000_000)
        XCTAssertEqual(motion.vy, Float(2350) * Float(2.625) * Float(0.032))
        XCTAssertEqual(motion.lastNs, 180_000_000)
        XCTAssertEqual(first.mayaAlpha.bitPattern, 0x3F791687)   // 1 - 0.75 * (0.18 / 5)
        // A frame later than 7 s ends the loop whatever the ball does.
        let late = motion.frame(now: 7_500_000_000)
        XCTAssertFalse(late.postAgain)
        XCTAssertEqual(late.mayaAlpha, 0.25)
        // A ball of size 0 has no spin (Kotlin `if (size > 0)`).
        var flat = TripleShotHomeBallMotion(rootWidth: 100, rootHeight: 100, size: 0, density: 1, nowNs: 0)
        XCTAssertNil(flat.frame(now: 180_000_000).rotationDelta)
    }

    // MARK: - Characters (Kotlin L337-379)

    private final class SizedDrawable: ADrawable {
        let w: Int
        let h: Int
        init(_ w: Int, _ h: Int) {
            self.w = w
            self.h = h
            super.init()
        }
        override var intrinsicWidth: Int { return w }
        override var intrinsicHeight: Int { return h }
    }

    private struct CharacterCase {
        let label: String
        let width: Int
        let height: Int
        let density: Float
        let maya: (Int, Int, UInt32, UInt32)
        let guest: (Int, Int, UInt32, UInt32)
        /// Without drawables: Maya width and x, guest width and x (y does not depend on the aspect).
        let fallback: (Int, UInt32, Int, UInt32)
    }

    private let characterCases: [CharacterCase] = [
        CharacterCase(label: "pixel6", width: 1080, height: 1920, density: 2.625,
                      maya: (358, 432, 0x444F599A, 0x44B9A000), guest: (296, 297, 0xC27C0000, 0x44CA6CCD),
                      fallback: (252, 0x4461E666, 244, 0xC256BF87)),
        CharacterCase(label: "iphone15", width: 1179, height: 2556, density: 3,
                      maya: (448, 540, 0x4458599A, 0x44FBA000), guest: (373, 375, 0xC2900000, 0x45082000),
                      fallback: (313, 0x446FF99A, 307, 0xC2874CCD)),
        CharacterCase(label: "ipad13", width: 2048, height: 2732, density: 2,
                      maya: (299, 360, 0x44E5D666, 0x45142000), guest: (249, 250, 0xC2400000, 0x451B0000),
                      fallback: (208, 0x44EDCCCD, 205, 0xC2346666)),
        CharacterCase(label: "se", width: 750, height: 1334, density: 2,
                      maya: (249, 300, 0x440FECCD, 0x4480FB33), guest: (206, 206, 0xC2356E21, 0x448CA75C),
                      fallback: (192, 0x4419E666, 169, 0xC215348A)),
        CharacterCase(label: "tiny", width: 100, height: 200, density: 3,
                      maya: (336, 405, 0x00000000, 0x00000000), guest: (275, 276, 0xC2722D0D, 0x00000000),
                      fallback: (288, 0x00000000, 226, 0xC247295E)),
    ]

    func testCharacterFramesMatchTheJvmGoldenVectors() {
        // triple_shot_home_maya.webp 255 x 307, triple_shot_home_unicorn32.webp 344 x 345 (drawable-nodpi).
        let mayaDrawable = SizedDrawable(255, 307)
        let guestDrawable = SizedDrawable(344, 345)
        for c in characterCases {
            let maya = TripleShotHomeFragment.mayaFrame(rootWidth: c.width, rootHeight: c.height,
                                                        drawable: mayaDrawable, density: c.density)
            XCTAssertEqual(maya.width, c.maya.0, "\(c.label) Maya width")
            XCTAssertEqual(maya.height, c.maya.1, "\(c.label) Maya height")
            XCTAssertEqual(maya.x.bitPattern, c.maya.2, "\(c.label) Maya x")
            XCTAssertEqual(maya.y.bitPattern, c.maya.3, "\(c.label) Maya y")

            let guest = TripleShotHomeFragment.guestFrame(rootWidth: c.width, rootHeight: c.height,
                                                          drawable: guestDrawable, density: c.density)
            XCTAssertEqual(guest.width, c.guest.0, "\(c.label) guest width")
            XCTAssertEqual(guest.height, c.guest.1, "\(c.label) guest height")
            XCTAssertEqual(guest.x.bitPattern, c.guest.2, "\(c.label) guest x")
            XCTAssertEqual(guest.y.bitPattern, c.guest.3, "\(c.label) guest y")

            // No drawable (or no intrinsic size): the 0.58 / 0.82 fallback aspects.
            let mayaFallback = TripleShotHomeFragment.mayaFrame(rootWidth: c.width, rootHeight: c.height,
                                                                drawable: nil, density: c.density)
            XCTAssertEqual(mayaFallback.width, c.fallback.0, "\(c.label) Maya fallback width")
            XCTAssertEqual(mayaFallback.x.bitPattern, c.fallback.1, "\(c.label) Maya fallback x")
            XCTAssertEqual(mayaFallback.y, maya.y)
            let guestFallback = TripleShotHomeFragment.guestFrame(rootWidth: c.width, rootHeight: c.height,
                                                                  drawable: SizedDrawable(-1, -1), density: c.density)
            XCTAssertEqual(guestFallback.width, c.fallback.2, "\(c.label) guest fallback width")
            XCTAssertEqual(guestFallback.x.bitPattern, c.fallback.3, "\(c.label) guest fallback x")
            XCTAssertEqual(guestFallback.y, guest.y)
        }
    }

    // MARK: - Topic button text (Kotlin L932-964)

    func testTopicButtonText() {
        for language in ["en", "he"] {
            let all = KLinkedSet(QuestionCategory.allCases)
            XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: all, language: language),
                           AResources.getString(R.string.minik_swish_topics_all))
            // All topics in another order are still "all" (set equality).
            XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: KLinkedSet(QuestionCategory.allCases.reversed()),
                                                                  language: language),
                           AResources.getString(R.string.minik_swish_topics_all))

            let prefix = AResources.getString(R.string.minik_swish_topics_prefix)
            let one: KLinkedSet<QuestionCategory> = [.HISTORY]
            XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: one, language: language),
                           prefix + " " + QuestionCategory.HISTORY.labelFor(languageCode: language))
            // Two topics: labels in ordinal order (SCIENCE before HISTORY), joined by " • " (U+2022).
            let two: KLinkedSet<QuestionCategory> = [.HISTORY, .SCIENCE]
            XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: two, language: language),
                           prefix + " " + QuestionCategory.SCIENCE.labelFor(languageCode: language) + " \u{2022} "
                               + QuestionCategory.HISTORY.labelFor(languageCode: language))

            let three: KLinkedSet<QuestionCategory> = [.MATH, .AI, .ENGLISH]
            XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: three, language: language),
                           AContextResources.shared.getQuantityString(R.plurals.minik_swish_topics_count, 3, 3))
            let ten = KLinkedSet(QuestionCategory.allCases.dropLast())
            XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: ten, language: language),
                           AContextResources.shared.getQuantityString(R.plurals.minik_swish_topics_count, 10, 10))
        }
        // The label language: English only for "en" (any case), Hebrew otherwise.
        let two: KLinkedSet<QuestionCategory> = [.SCIENCE]
        XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: two, language: "fr"),
                       TripleShotHomeFragment.topicButtonText(selectedCategories: two, language: "he"))
        XCTAssertEqual(TripleShotHomeFragment.topicButtonText(selectedCategories: two, language: "EN"),
                       TripleShotHomeFragment.topicButtonText(selectedCategories: two, language: "en"))
    }

    // MARK: - Fragments and layouts

    func testScreensInflateTheirLayouts() {
        let home = TripleShotHomeFragment()
        XCTAssertEqual(home.contentLayoutId, R.layout.fragment_triple_shot_home)
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.fragment_triple_shot_home))
        let host = TripleShotHostFragment()
        XCTAssertEqual(host.contentLayoutId, R.layout.fragment_triple_shot_host)
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.fragment_triple_shot_host))
        let activity = TripleShotDemoActivity()
        XCTAssertEqual(activity.contentLayoutId, R.layout.activity_triple_shot_demo)
        XCTAssertTrue(ALayoutInflater.isRegistered(R.layout.activity_triple_shot_demo))
    }

    func testDemoAndHostLayoutsMatchTheXml() throws {
        let demo = try XCTUnwrap(TripleShotDemoLayout.build() as? AFrameLayout)
        XCTAssertEqual(demo.viewId, R.id.tripleShotDemoContainer)
        XCTAssertEqual(demo.layoutParams?.width, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(demo.layoutParams?.height, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(demo.childCount, 0)

        let host = try XCTUnwrap(TripleShotHostLayout.build() as? AFrameLayout)
        XCTAssertEqual(host.viewId, R.id.tripleShotChildContainer)
        XCTAssertEqual(host.layoutParams?.width, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(host.layoutParams?.height, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(host.childCount, 0)
    }

    func testHomeLayoutTreeMatchesTheXml() throws {
        let px = { (dp: Float) -> Int in ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp) }
        let spPx = { (sp: Float) -> Float in Float(ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_SP, sp)) }
        let dimen = { (dp: Float) -> Float in ATypedValue.applyDimension(ATypedValue.COMPLEX_UNIT_DIP, dp) }
        let PARENT = AConstraintLayout.LayoutParams.PARENT_ID

        let root = try XCTUnwrap(TripleShotHomeLayout.build() as? AConstraintLayout)
        XCTAssertEqual(root.layoutParams?.width, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual(root.layoutParams?.height, AViewGroup.LayoutParams.MATCH_PARENT)
        XCTAssertEqual((root.background as? AColorDrawable)?.color, AColor.parseColor("#FFFDF5"))
        XCTAssertEqual(root.children.map { $0.viewId ?? "" }, [R.id.homeBackground, R.id.homeFixedHeader, R.id.homeScroll])

        // Scenery.
        let background: AImageView = try XCTUnwrap(root.findViewById(R.id.homeBackground))
        XCTAssertEqual(background.scaleType, AImageView.ScaleType.CENTER_CROP)
        XCTAssertEqual(background.getAlpha(), 0.42)
        XCTAssertNil(background.contentDescription)
        let backgroundParams = try XCTUnwrap(background.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual([backgroundParams.width, backgroundParams.height], [0, 0])
        XCTAssertEqual([backgroundParams.topToTop, backgroundParams.bottomToBottom, backgroundParams.startToStart,
                        backgroundParams.endToEnd], [PARENT, PARENT, PARENT, PARENT])

        // Header.
        let header: ALinearLayout = try XCTUnwrap(root.findViewById(R.id.homeFixedHeader))
        XCTAssertEqual(header.orientation, ALinearLayout.VERTICAL)
        // LinearLayout.setGravity adds the missing vertical part (TOP).
        XCTAssertEqual(header.gravity, AGravity.CENTER_HORIZONTAL | AGravity.TOP)
        XCTAssertEqual(header.paddingTop, px(34))
        XCTAssertEqual(header.paddingBottom, px(8))
        XCTAssertEqual(header.paddingStart, px(20))
        XCTAssertEqual(header.paddingEnd, px(20))
        XCTAssertEqual(header.children.map { $0.viewId ?? "" }, [R.id.homeTitle, R.id.homeSubtitle])
        let title = try XCTUnwrap(root.findViewById(R.id.homeTitle) as OutlinedTitleView?)
        XCTAssertEqual(title.text, AResources.getString(R.string.triple_shot_title))
        XCTAssertEqual(title.textSize, spPx(32))
        XCTAssertEqual(title.currentTextColor, R.color.triple_shot_ink)
        let subtitle: ATextView = try XCTUnwrap(root.findViewById(R.id.homeSubtitle))
        XCTAssertEqual(subtitle.textSize, spPx(17))
        XCTAssertEqual(subtitle.currentTextColor, R.color.triple_shot_green)
        XCTAssertEqual((subtitle.layoutParams as? ALinearLayout.LayoutParams)?.topMargin, px(2))

        // Scroll column.
        let scroll: AScrollView = try XCTUnwrap(root.findViewById(R.id.homeScroll))
        XCTAssertTrue(scroll.isFillViewport)
        XCTAssertFalse(scroll.clipToPadding)
        XCTAssertEqual(scroll.overScrollMode, AView.OVER_SCROLL_NEVER)
        let scrollParams = try XCTUnwrap(scroll.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(scrollParams.topToBottom, R.id.homeFixedHeader)
        XCTAssertEqual(scrollParams.bottomToBottom, PARENT)
        let column = try XCTUnwrap(scroll.getChildAt(0) as? AConstraintLayout)
        XCTAssertEqual(column.minimumHeight, px(640))
        XCTAssertEqual(column.paddingBottom, px(30))
        let content: ALinearLayout = try XCTUnwrap(root.findViewById(R.id.homeContent))
        let contentParams = try XCTUnwrap(content.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(contentParams.width, 0)
        XCTAssertEqual(contentParams.matchConstraintMaxWidth, px(520))
        XCTAssertEqual(contentParams.marginStart, px(20))
        XCTAssertEqual(contentParams.marginEnd, px(20))
        XCTAssertEqual(contentParams.topMargin, px(6))
        XCTAssertEqual(content.children.count, 4)
        XCTAssertEqual(content.children.dropFirst().map { $0.viewId ?? "" },
                       [R.id.roomPanel, R.id.aiDisclaimerText, R.id.infoPrivacyButton])

        // The old card: name field, Stats | Topics, practice, cloud practice (gone), bot, divider, create, join row,
        // leaderboard.
        let card = try XCTUnwrap(content.getChildAt(0) as? ACardView)
        XCTAssertEqual(card.radius, dimen(22))
        XCTAssertEqual(card.strokeWidth, px(2))
        XCTAssertEqual((card.layoutParams as? ALinearLayout.LayoutParams)?.topMargin, px(20))
        let body = try XCTUnwrap(card.getChildAt(0) as? ALinearLayout)
        XCTAssertEqual(body.paddingLeft, px(16))
        XCTAssertEqual(body.childCount, 9)

        let nameInput: AEditText = try XCTUnwrap(root.findViewById(R.id.playerNameInput))
        XCTAssertTrue(nameInput is ATextInputEditText)
        XCTAssertTrue(nameInput.parentGroup?.parentGroup is ATextInputLayout)
        XCTAssertEqual(nameInput.imeOptions, AEditorInfo.IME_ACTION_DONE)
        XCTAssertTrue(nameInput.isSingleLine)
        XCTAssertEqual((nameInput.filters.first as? ALengthFilter)?.max, 18)

        let stats: AButton = try XCTUnwrap(root.findViewById(R.id.statsButton))
        XCTAssertEqual((stats.layoutParams as? ALinearLayout.LayoutParams)?.weight, 0.38)
        XCTAssertEqual(stats.layoutParams?.height, px(52))
        XCTAssertFalse(stats.isAllCaps)
        let topic: AButton = try XCTUnwrap(root.findViewById(R.id.topicButton))
        XCTAssertEqual((topic.layoutParams as? ALinearLayout.LayoutParams)?.weight, 0.62)
        XCTAssertEqual(topic.maxLines, 2)
        XCTAssertEqual(topic.iconGravity, AButton.ICON_GRAVITY_TEXT_START)
        XCTAssertNotNil(topic.icon)
        XCTAssertEqual(topic.text, AResources.getString(R.string.minik_swish_topics_all))

        let practice: AButton = try XCTUnwrap(root.findViewById(R.id.practiceButton))
        XCTAssertEqual(practice.layoutParams?.height, px(54))
        XCTAssertEqual(practice.textSize, spPx(18))
        XCTAssertEqual(practice.text, AResources.getString(R.string.minik_swish_practice))
        let cloud: AButton = try XCTUnwrap(root.findViewById(R.id.cloudPracticeButton))
        XCTAssertEqual(cloud.visibility, AView.GONE)
        let bot: AButton = try XCTUnwrap(root.findViewById(R.id.botButton))
        XCTAssertEqual(bot.layoutParams?.height, px(50))
        let create: AButton = try XCTUnwrap(root.findViewById(R.id.createRoomButton))
        XCTAssertEqual(create.text, AResources.getString(R.string.triple_shot_create_room))

        let codeInput: AEditText = try XCTUnwrap(root.findViewById(R.id.roomCodeInput))
        XCTAssertEqual(codeInput.inputType & AInputType.TYPE_TEXT_FLAG_CAP_CHARACTERS, AInputType.TYPE_TEXT_FLAG_CAP_CHARACTERS)
        XCTAssertEqual((codeInput.filters.first as? ALengthFilter)?.max, 6)
        let join: AButton = try XCTUnwrap(root.findViewById(R.id.joinRoomButton))
        XCTAssertEqual(join.layoutParams?.height, px(52))
        XCTAssertEqual(join.layoutParams?.width, AViewGroup.LayoutParams.WRAP_CONTENT)
        XCTAssertEqual((join.layoutParams as? ALinearLayout.LayoutParams)?.marginStart, px(8))
        let joinRow = try XCTUnwrap(join.parentGroup as? ALinearLayout)
        XCTAssertEqual(joinRow.orientation, ALinearLayout.HORIZONTAL)
        XCTAssertEqual((joinRow.getChildAt(0)?.layoutParams as? ALinearLayout.LayoutParams)?.weight, 1)

        let leaderboard: AButton = try XCTUnwrap(root.findViewById(R.id.leaderboardButton))
        XCTAssertEqual((leaderboard.layoutParams as? ALinearLayout.LayoutParams)?.topMargin, px(10))

        // Room panel (+ the iOS-only Leave control).
        let panel: ACardView = try XCTUnwrap(root.findViewById(R.id.roomPanel))
        XCTAssertEqual(panel.visibility, AView.GONE)
        XCTAssertEqual(panel.radius, dimen(20))
        let panelBody = try XCTUnwrap(panel.getChildAt(0) as? ALinearLayout)
        XCTAssertEqual(panelBody.children.map { $0.viewId ?? "" },
                       [R.id.roomStatusText, R.id.roomPlayersText, R.id.startRoomButton,
                        TripleShotHomeFragment.IOS_LEAVE_ROOM_BUTTON_ID])
        let start: AButton = try XCTUnwrap(root.findViewById(R.id.startRoomButton))
        XCTAssertEqual(start.visibility, AView.GONE)
        XCTAssertEqual(start.layoutParams?.height, px(48))
        let leave: AButton = try XCTUnwrap(root.findViewById(TripleShotHomeFragment.IOS_LEAVE_ROOM_BUTTON_ID))
        XCTAssertEqual(leave.visibility, AView.VISIBLE)
        XCTAssertEqual(leave.layoutParams?.height, px(48))
        XCTAssertFalse(leave.text.isEmpty)

        // Footer.
        let disclaimer: ATextView = try XCTUnwrap(root.findViewById(R.id.aiDisclaimerText))
        XCTAssertEqual(disclaimer.textSize, spPx(16))
        XCTAssertEqual(disclaimer.textAlignment, AView.TEXT_ALIGNMENT_VIEW_START)
        XCTAssertEqual((disclaimer.layoutParams as? ALinearLayout.LayoutParams)?.topMargin, px(14))
        let info: AButton = try XCTUnwrap(root.findViewById(R.id.infoPrivacyButton))
        XCTAssertEqual(info.layoutParams?.height, px(44))
        XCTAssertEqual(info.currentTextColor, R.color.triple_shot_purple)
    }

    func testTopicsIconIsAThirtyTwoDpFrameworkSizedBitmap() throws {
        let icon = try XCTUnwrap(TripleShotHomeLayout.icMenuManage())
        let side = ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, 32)
        XCTAssertEqual(icon.intrinsicWidth, side)
        XCTAssertEqual(icon.intrinsicHeight, side)
    }

    // MARK: - iOS-only safe area (spec 18 §4.4.3 / §10.4, §4.4.9)

    func testHomeKeepsItsHeaderAndColumnOutOfTheIosSystemBars() throws {
        let px = { (dp: Float) -> Int in ATypedValue.toDimensionPixelSize(ATypedValue.COMPLEX_UNIT_DIP, dp) }
        let pt = { (points: Float) -> Int in (points * AResources.displayMetrics.density).roundToInt() }
        let root = try XCTUnwrap(TripleShotHomeLayout.build() as? AConstraintLayout)
        let header: ALinearLayout = try XCTUnwrap(root.findViewById(R.id.homeFixedHeader))
        let scroll: AScrollView = try XCTUnwrap(root.findViewById(R.id.homeScroll))
        let scrollParams = try XCTUnwrap(scroll.layoutParams as? AConstraintLayout.LayoutParams)
        XCTAssertEqual(header.paddingTop, px(34))
        XCTAssertEqual(scrollParams.bottomMargin, 0)

        // A Dynamic Island iPhone in portrait: a 59 pt status bar and a 34 pt home indicator.
        _ = root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 0, top: pt(59), right: 0, bottom: pt(34), statusBarVisible: true, imeBottom: 0))
        XCTAssertEqual(header.paddingTop, pt(59) + px(8))
        XCTAssertEqual(header.paddingBottom, px(8))
        XCTAssertEqual(header.paddingStart, px(20))
        XCTAssertEqual(header.paddingEnd, px(20))
        XCTAssertEqual(scrollParams.bottomMargin, pt(34))
        XCTAssertEqual(scrollParams.leftMargin, 0)
        XCTAssertEqual(scrollParams.rightMargin, 0)

        // The keyboard is not avoided (Android 15+ edge-to-edge does not resize the Home for the IME either).
        _ = root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 0, top: pt(59), right: 0, bottom: pt(34), statusBarVisible: true, imeBottom: pt(300)))
        XCTAssertEqual(scrollParams.bottomMargin, pt(34))

        // A 20 pt status bar without a home indicator (iPhone SE) keeps Android's 34 dp and the full-height column.
        _ = root.dispatchApplyWindowInsets(AWindowInsetsCompat.fromSafeArea(
            left: 0, top: pt(20), right: 0, bottom: 0, statusBarVisible: true, imeBottom: 0))
        XCTAssertEqual(header.paddingTop, px(34))
        XCTAssertEqual(scrollParams.bottomMargin, 0)
    }
}
