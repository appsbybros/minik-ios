import SwiftUI
import SpriteKit
import AVFoundation

// Shared presentation of Multi Ping Pong 5c1aa4d: the menu sections and links (Android FamilyMenu), the sunset scenery
// (SunsetTerrace), the match layout and toolbar (MatchSceneLayout / MatchToolbar), whole-body portraits (BotPortrait), the team
// celebration (TeamVictoryView), the reception assistance switches (ReceptionSettings) and the quiet menu music (PongMenuMusic).

/// Android FamilyMenu colours.
enum MPXMenu {
    static let learn = Color(red: 0xb8 / 255, green: 0xd9 / 255, blue: 1)
    static let play = Color(red: 0xb9 / 255, green: 0xf4 / 255, blue: 0xdc / 255)
    static let saved = Color(red: 0xe8 / 255, green: 0xdc / 255, blue: 1)
    static let advanced = Color(red: 1, green: 0xe0 / 255, blue: 0x82 / 255)
    static let link = Color(red: 0x28 / 255, green: 0x69 / 255, blue: 0xbd / 255)
    static let ink = Color(red: 0x28 / 255, green: 0x2d / 255, blue: 0x4e / 255)
    /// Team and journey pages (Android `0xff173e56`).
    static let deepInk = Color(red: 0x17 / 255, green: 0x3e / 255, blue: 0x56 / 255)
    static let cyan = Color(red: 0xb8 / 255, green: 0xee / 255, blue: 0xe4 / 255)
    static let gold = Color(red: 0xb8 / 255, green: 0xd9 / 255, blue: 1)
    static let mint = Color(red: 189 / 255, green: 244 / 255, blue: 231 / 255)
    static let pink = Color(red: 233 / 255, green: 30 / 255, blue: 99 / 255)
    static let panel = Color(red: 0xf4 / 255, green: 0xf8 / 255, blue: 0xfc / 255)
    static let status = Color(red: 14 / 255, green: 31 / 255, blue: 57 / 255).opacity(195 / 255)
    static let hud = Color(red: 0x19 / 255, green: 0x30 / 255, blue: 0x4a / 255).opacity(0xd0 / 255)
}

/// Android FamilyMenu.section: a coloured, collapsible menu group whose open state is remembered by its title.
struct MPXSection<Content: View>: View {
    let title: String
    let color: Color
    let preferences: MPPreferences
    let defaultOpen: Bool
    @ViewBuilder let content: () -> Content
    @State private var open: Bool?
    var body: some View {
        let shown = open ?? preferences.menuSection(title, default: defaultOpen)
        VStack(spacing: 8) {
            Button {
                let next = !shown
                open = next
                preferences.setMenuSection(title, next)
            } label: {
                HStack {
                    Text(title).font(.system(size: 21, weight: .bold)).foregroundStyle(MPXMenu.ink)
                    Spacer()
                    Text(shown ? "−" : "+").font(.system(size: 26, weight: .bold)).foregroundStyle(MPXMenu.ink).frame(width: 42, height: 48)
                }.frame(minHeight: 54).padding(.horizontal, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title + (shown ? ", −" : ", +"))
            if shown { VStack(spacing: 12) { content() }.padding(.bottom, 8) }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color, lineWidth: 2))
    }
}

/// Android FamilyMenu.link: a quiet underlined link on a light backing.
struct MPXLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .bold)).underline().foregroundStyle(MPXMenu.link)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(red: 0xf7 / 255, green: 0xfb / 255, blue: 1).opacity(0xee / 255), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

/// Android FamilyTournamentUi.divider: a dashed line between creating and joining.
struct MPXDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: geo.size.width, y: 1)) }
                .stroke(Color(red: 0x78 / 255, green: 0x92 / 255, blue: 0xad / 255), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        }.frame(height: 2).padding(.horizontal, 8).padding(.vertical, 24).accessibilityHidden(true)
    }
}

/// Android SunsetTerrace: the evening terrace behind matches and room screens, or (menu) the integrated menu painting. Aspect
/// fill, top aligned, over the night-to-sand gradient of LocalizedActivity.
struct MPXSunsetBackground: View {
    var menu = false
    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let name = menu ? (landscape ? "mpx_menu_landscape" : "mpx_menu_portrait") : (landscape ? "mpx_sunset_landscape" : "mpx_sunset_portrait")
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 17 / 255, green: 29 / 255, blue: 57 / 255), Color(red: 29 / 255, green: 71 / 255, blue: 86 / 255),
                                        Color(red: 218 / 255, green: 182 / 255, blue: 119 / 255)], startPoint: .top, endPoint: .bottom)
                if let image = UIImage(named: name) {
                    let scale = max(proxy.size.width / max(1, image.size.width), proxy.size.height / max(1, image.size.height))
                    Image(uiImage: image).resizable().frame(width: image.size.width * scale, height: image.size.height * scale)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top).clipped()
                }
            }
        }.accessibilityHidden(true)
    }
}

/// Android MatchSceneLayout + MatchToolbar: portrait = a toolbar row, the status and the court; landscape = a side dock (two
/// toolbar columns and the status) beside the court. The same court keeps its engine and input across a rotation.
struct MPXMatchLayout<Tools: View, Status: View, Court: View>: View {
    let tools: Int
    @ViewBuilder let toolbar: () -> Tools
    @ViewBuilder let status: (_ wide: Bool) -> Status
    @ViewBuilder let court: () -> Court
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let side = wide ? min(140, geo.size.width / 4) : geo.size.width
            let columns = max(1, min(tools, side < 300 ? 2 : 6))
            let grid = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 6) { toolbar() }
                .padding(.horizontal, 2).padding(.vertical, 3)
            if wide {
                HStack(spacing: 0) {
                    VStack(spacing: 6) { grid; status(true); Spacer(minLength: 0) }.frame(width: side)
                    court().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) { grid; status(false); court().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }
}

/// A 48 pt toolbar control: an SF Symbol on a coloured, rounded surface.
struct MPXTool: View {
    let symbol: String
    let label: String
    let fill: Color
    var tint: Color = .white
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.bold()).foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .background(fill, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// The court with a transparent background over the sunset terrace.
struct MPXCourt: View {
    let scene: CrossScene
    let label: String
    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency]).id(ObjectIdentifier(scene))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(label)
    }
}

/// Android BotPortrait (5c1aa4d): the character's first standing pose.
struct MPXPortrait: View {
    let character: String
    var body: some View {
        Group {
            if let image = MPXPortrait.image(character) { Image(uiImage: image).resizable().scaledToFit().padding(2) }
            else { MPAvatar(character: character, icon: 0) }
        }.accessibilityHidden(true)
    }
    private static var cache: [String: UIImage] = [:]
    static func image(_ id: String) -> UIImage? {
        if let known = cache[id] { return known }
        guard !id.isEmpty, let value = MPXPoseAtlas.shared.portrait(id) else { return nil }
        cache[id] = value
        return value
    }
}

/// Android TeamVictoryView: the two teammates jump together, then settle into a lasting team portrait among confetti.
struct MPXTeamVictory: View {
    let characters: [String]
    @State private var born = Date()
    var body: some View {
        let art = Array(characters.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(2))
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
            let seconds = timeline.date.timeIntervalSince(born)
            Canvas { context, size in
                let motion = !UIAccessibility.isReduceMotionEnabled && seconds < 2.4
                let jump: CGFloat = motion ? CGFloat(max(0, sin(seconds * Double.pi / 0.8))) * size.height * 0.12 : 0
                let colors: [Color] = [Color(red: 1, green: 0xd7 / 255, blue: 0x6a / 255), Color(red: 0xb7 / 255, green: 0x35 / 255, blue: 0x78 / 255),
                              Color(red: 0x36 / 255, green: 0x8d / 255, blue: 0xec / 255), Color(red: 0x4f / 255, green: 0xca / 255, blue: 0xa3 / 255)]
                for i in 0..<36 {
                    let x: CGFloat = size.width * CGFloat(i * 37 % 101) / 101, y: CGFloat = size.height * CGFloat(i * 23 % 103) / 103
                    var piece = context
                    piece.translateBy(x: x, y: y); piece.rotate(by: .degrees(Double(i) * 31))
                    piece.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 5, height: 10), cornerRadius: 2), with: .color(colors[i % 4].opacity(190 / 255)))
                }
                for (i, id) in art.enumerated() {
                    guard let image = UIImage(named: "mpx_team_" + id) else { continue }
                    let maxH: CGFloat = size.height * 0.79, maxW: CGFloat = size.width / (CGFloat(art.count) + 0.35)
                    let s: CGFloat = min(maxH / image.size.height, maxW / image.size.width)
                    let w = image.size.width * s, h = image.size.height * s
                    let place: CGFloat = art.count == 1 ? 0.5 : (i == 0 ? 0.32 : 0.68)
                    let cx: CGFloat = size.width * place, bottom: CGFloat = size.height * 0.96 - jump
                    context.fill(Path(ellipseIn: CGRect(x: cx - w * 0.27, y: size.height * 0.94, width: w * 0.54, height: size.height * 0.04)),
                                 with: .color(Color(red: 0x13 / 255, green: 0x29 / 255, blue: 0x26 / 255).opacity(0x28 / 255)))
                    context.draw(Image(uiImage: image), in: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h))
                }
            }
        }
        .accessibilityLabel(MPText.language == "he" ? "חברי הקבוצה חוגגים יחד" : "Your teammates celebrate together")
    }
}

/// Android ReceptionSettings.add: "Ball assistance ▾" opens three switches and their explanations.
struct MPXReceptionSettings: View {
    let preferences: MPPreferences
    let hebrew: Bool
    @State private var open = false
    @State private var zoom = false
    @State private var slow = false
    @State private var follow = false
    private func tr(_ en: String, _ he: String) -> String { MPText.t(en, he, hebrew) }
    var body: some View {
        VStack(spacing: 8) {
            Button { open.toggle() } label: {
                Text(tr("Ball assistance ▾", "עזרה בקבלת הכדור ▾")).font(.headline).foregroundStyle(MPXMenu.deepInk).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(white: 0.93), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    toggle(tr("Zoom in for my return", "מיקוד המצלמה לקראת החבטה שלי"), $zoom) { preferences.receptionZoom = $0 }
                    note(tr("Bring the camera closer as the ball approaches you, then return to the full table.", "המצלמה מתקרבת כשהכדור מגיע אליכם, ואז חוזרת למבט על השולחן."))
                    toggle(tr("Gentle slow motion for my return", "האטה הדרגתית לקראת החבטה שלי"), $slow) { preferences.receptionSlow = $0 }
                    note(tr("Slow the whole game briefly for your return. Online, everyone shares the same pace.", "מאטים לזמן קצר את המשחק לקראת החבטה שלכם. ברשת, כולם משחקים באותה מהירות."))
                    toggle(tr("Zoom in for another player's return (not bots)", "מיקוד המצלמה כששחקן אחר מקבל את הכדור"), $follow) { preferences.receptionFollow = $0 }
                    note(tr("During online play, zoom in when another player receives the ball. Bot turns keep the normal view.", "במשחק מקוון, מתקרבים כששחקן אחר מקבל את הכדור. בתור של שחקן בית המבט נשאר רגיל."))
                    Text(tr("Online players share the same game speed. Each player chooses slow motion for their own return. Camera choices affect only your screen; bots do not trigger zoom.",
                            "במשחק ברשת כולם משחקים באותה מהירות. כל שחקן בוחר אם להאט לקראת החבטה שלו. אפשרויות המצלמה משפיעות רק על המסך שלכם; אין התקרבות לקראת חבטות של בוטים."))
                        .font(.system(size: 15)).foregroundStyle(MPXMenu.deepInk)
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .onAppear { zoom = preferences.receptionZoom; slow = preferences.receptionSlow; follow = preferences.receptionFollow }
    }
    private func toggle(_ title: String, _ value: Binding<Bool>, _ save: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; save($0) })) {
            Text(title).font(.system(size: 17)).foregroundStyle(MPXMenu.deepInk)
        }.frame(minHeight: 56)
    }
    private func note(_ text: String) -> some View { Text(text).font(.system(size: 14)).foregroundStyle(MPXMenu.deepInk).padding(.bottom, 12) }
}

/// Android PongMenuMusic: a quiet looping menu remix, only while the menu is shown, the app is active and music is on.
@MainActor final class MPXMenuMusic {
    private var player: AVAudioPlayer?
    func set(_ playing: Bool) {
        guard playing else { player?.pause(); return }
        if player == nil, let data = NSDataAsset(name: "mpx_menu_music")?.data, let made = try? AVAudioPlayer(data: data) {
            made.numberOfLoops = -1; made.volume = 0.22; made.prepareToPlay(); player = made
        }
        if player?.isPlaying == false { player?.play() }
    }
    func stop() { player?.stop(); player = nil }
}

/// A system share sheet for a text.
struct MPXShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
