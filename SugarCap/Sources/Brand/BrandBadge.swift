import SwiftUI

/// 브랜드 배지(2026-11-10 대표님): 대표색 원 + 그 브랜드가 떠오르는 글자나 모양 하나. 로고 그림은 그대로 옮기지 않는다.
/// 시안은 HTML/SVG로 먼저 그려 확정했고, 좌표는 그 시안의 100×100 칸을 그대로 쓴다.
/// 색·모양은 카탈로그가 아니라 여기서 정한다(카탈로그는 파이프라인 산출물이라 손으로 고치지 않는다).
/// 표에 없는 브랜드는 회색 원 + 이름 첫 글자.
struct BrandBadge: View {
    let brand: Brand
    var size: CGFloat = 40

    var body: some View {
        let design = BrandBadgeDesign.of(brand)
        Canvas { context, canvas in
            let scale = canvas.width / 100
            let disc = Path(ellipseIn: CGRect(x: 1, y: 1, width: 98, height: 98)).scaled(scale)
            context.fill(disc, with: .color(design.background))
            var inside = context
            inside.clip(to: disc)
            for mark in design.marks {
                mark.draw(in: inside, scale: scale, ink: design.ink, background: design.background)
            }
            context.stroke(disc, with: .color(.black.opacity(0.08)), lineWidth: 1.5 * scale)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BrandBadgeDesign {
    let background: Color
    let ink: Color
    let marks: [BadgeMark]

    static func of(_ brand: Brand) -> BrandBadgeDesign {
        if let design = table[brand.id] { return design }
        let initial = String(brand.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return BrandBadgeDesign(background: Color(.systemGray5), ink: .secondary, marks: [.text(initial, .pretendardBold, 44)])
    }

    private static func make(_ background: String, _ ink: String, _ marks: [BadgeMark]) -> BrandBadgeDesign {
        BrandBadgeDesign(background: Color(liquidHex: background) ?? Color(.systemGray5), ink: Color(liquidHex: ink) ?? .white, marks: marks)
    }

    private static let starbucks = make("#00A862", "#FFFFFF", [.ring(radius: 36, width: 4), .star])

    /// 색·모양은 2026-11-10 각 브랜드 앱스토어 아이콘과 나란히 놓고 맞췄다. 可不可는 대조할 앱이 없어 그 전 모양이다.
    private static let table: [String: BrandBadgeDesign] = [
        DrinkTutorial.brandID: make("#5B84AA", "#FFFFFF", [.text("슈", .pretendardBlack, 48, dy: 2)]),
        "starbucks": starbucks,
        "mega": make("#FFD200", "#1A1A1A", [.text("MGC", .archivo, 30)]),
        "compose": make("#F6C90E", "#1A1A1A", [
            .disc(x: 50, y: 50, radius: 31), .tinted("#F6C90E", .compass), .disc(x: 50, y: 50, radius: 3.5),
        ]),
        "ediya": make("#2B44C0", "#FFFFFF", [.text("EDIYA", .archivo, 19, tracking: 0.5)]),
        "paik": make("#FFD400", "#1B3A8C", [.text("빽", .pretendardBlack, 52, dy: 2)]),
        "twosome": make("#E31E2D", "#FFFFFF", [
            .tinted("#6D6E71", .rect(x: 0, y: 0, width: 50, height: 50, corner: 0)),
            .tinted("#6D6E71", .rect(x: 50, y: 50, width: 50, height: 50, corner: 0)),
            .tinted("#1A1A1A", .rect(x: 0, y: 40, width: 100, height: 20, corner: 0)),
            .text("TWOSOME", .archivo, 12, dy: 0.5, tracking: 0.3),
        ]),
        "hollys": make("#FFFFFF", "#D2232A", [
            .crown(x: 27, y: 36, width: 46, height: 30), .disc(x: 27, y: 42, radius: 3.5), .disc(x: 73, y: 42, radius: 3.5),
        ]),
        "theventi": make("#EEDFF2", "#6A2C91", [.text("the", .pretendardBold, 17, dy: -13), .text("Venti", .archivo, 23, dy: 8)]),
        "gongcha": make("#3B302C", "#FFFFFF", [
            .tinted("#C8102E", .rect(x: 35, y: 20, width: 30, height: 60, corner: 3)),
            .text("貢", .pretendardBold, 22, dy: -13), .text("茶", .pretendardBold, 22, dy: 13),
        ]),
        "cvs": make("#E9ECF0", "#8E8E93", [.store]),
        "paulbassett": make("#111111", "#E8175D", [
            .crown(x: 20, y: 32, width: 60, height: 30, peaks: 5, tipDrop: 0.9, valley: 0.72),
            .disc(x: 20, y: 41.5, radius: 3.2), .disc(x: 35, y: 34.75, radius: 3.2), .disc(x: 50, y: 28, radius: 3.2),
            .disc(x: 65, y: 34.75, radius: 3.2), .disc(x: 80, y: 41.5, radius: 3.2),
        ]),
        "baskin": make("#FFFFFF", "#F25C9A", [.text("BR", .archivo, 44)]),
        "coffeebean": make("#5E2C82", "#FFFFFF", [.bean]),
        "parisbaguette": make("#0D2F7A", "#FFFFFF", [.frame(x: 27, y: 27, width: 46, height: 46, corner: 6, lineWidth: 3), .text("B", .archivo, 40, dy: 1)]),
        "bluebottle": make("#FFFFFF", "#00A6E0", [.bottle]),
        "amasvin": make("#1E86C8", "#1A1A1A", [
            .disc(x: 50, y: 64, radius: 32),
            .tinted("#FFFFFF", .disc(x: 40, y: 60, radius: 3.5)), .tinted("#FFFFFF", .disc(x: 60, y: 60, radius: 3.5)),
            .tinted("#FFD23F", .crown(x: 39, y: 22, width: 22, height: 13)),
        ]),
        "oozy": make("#1B3D20", "#FFFFFF", [.text("OOZY", .anton, 34)]),
        "us-starbucks": starbucks,
        "us-dutchbros": make("#00649F", "#FFFFFF", [.windmill]),
        "tw-cama": make("#F5A800", "#1A1A1A", [.ring(radius: 38, width: 4), .camaFace]),
        "tw-kebuke": make("#1F1F1F", "#D8B36A", [.text("可", .pretendardBold, 48, dy: 2)]),
    ]
}

/// 배지 위의 글자·모양 하나. 좌표·크기는 100×100 칸 기준이고 그릴 때 배지 크기로 늘린다.
indirect enum BadgeMark {
    case text(String, BadgeFace, CGFloat, dy: CGFloat = 0, tracking: CGFloat = 0)
    case ring(radius: CGFloat, width: CGFloat)
    case disc(x: CGFloat, y: CGFloat, radius: CGFloat)
    case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, corner: CGFloat)
    case frame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, corner: CGFloat, lineWidth: CGFloat)
    /// 꼭짓점 `peaks`개. 가운데 꼭짓점이 맨 위, 양 끝으로 갈수록 높이의 `tipDrop`배만큼 내려오고, 골은 높이의 `valley` 지점.
    case crown(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, peaks: Int = 3, tipDrop: CGFloat = 0.4, valley: CGFloat = 0.55)
    case star
    case bean
    case bottle
    case store
    case compass
    case windmill
    case camaFace
    /// 안쪽 모양을 배지 글자색 대신 이 색으로 칠한다.
    case tinted(String, BadgeMark)

    func draw(in context: GraphicsContext, scale: CGFloat, ink: Color, background: Color) {
        switch self {
        case let .tinted(hex, mark):
            mark.draw(in: context, scale: scale, ink: Color(liquidHex: hex) ?? ink, background: background)
        case let .disc(x, y, radius):
            let disc = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            context.fill(disc.scaled(scale), with: .color(ink))
        case let .rect(x, y, width, height, corner):
            let rect = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: corner)
            context.fill(rect.scaled(scale), with: .color(ink))
        case let .frame(x, y, width, height, corner, lineWidth):
            let rect = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: corner)
            context.stroke(rect.scaled(scale), with: .color(ink), lineWidth: lineWidth * scale)
        case let .crown(x, y, width, height, peaks, tipDrop, valley):
            let gap = 1 / CGFloat(peaks - 1)
            var points = [CGPoint(x: x, y: y + height)]
            for index in 0..<peaks {
                let t = CGFloat(index) * gap
                points.append(CGPoint(x: x + t * width, y: y + abs(t - 0.5) * tipDrop * height))
                if index < peaks - 1 {
                    points.append(CGPoint(x: x + (t + gap / 2) * width, y: y + valley * height))
                }
            }
            points.append(CGPoint(x: x + width, y: y + height))
            var crown = Path()
            crown.addLines(points)
            crown.closeSubpath()
            context.fill(crown.scaled(scale), with: .color(ink))
        case .compass:
            var needle = Path()
            needle.addLines([CGPoint(x: 50, y: 26), CGPoint(x: 57, y: 50), CGPoint(x: 50, y: 74), CGPoint(x: 43, y: 50)])
            needle.closeSubpath()
            context.fill(needle.rotated(degrees: 45, around: CGPoint(x: 50, y: 50)).scaled(scale), with: .color(ink))
        case .camaFace:
            var head = Path()
            head.move(to: CGPoint(x: 31, y: 82))
            head.addCurve(to: CGPoint(x: 30, y: 37), control1: CGPoint(x: 28, y: 64), control2: CGPoint(x: 25, y: 46))
            head.addCurve(to: CGPoint(x: 55, y: 33), control1: CGPoint(x: 35, y: 28), control2: CGPoint(x: 48, y: 27))
            head.addCurve(to: CGPoint(x: 72, y: 40), control1: CGPoint(x: 61, y: 28), control2: CGPoint(x: 72, y: 31))
            head.addCurve(to: CGPoint(x: 61, y: 52), control1: CGPoint(x: 72, y: 48), control2: CGPoint(x: 64, y: 50))
            head.addCurve(to: CGPoint(x: 63, y: 82), control1: CGPoint(x: 60, y: 64), control2: CGPoint(x: 61, y: 74))
            context.stroke(head.scaled(scale), with: .color(ink), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
            var face = Path()
            face.move(to: CGPoint(x: 42, y: 40))
            face.addQuadCurve(to: CGPoint(x: 48, y: 40), control: CGPoint(x: 45, y: 43))
            face.move(to: CGPoint(x: 50, y: 47))
            face.addQuadCurve(to: CGPoint(x: 58, y: 47), control: CGPoint(x: 54, y: 50))
            context.stroke(face.scaled(scale), with: .color(ink), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
            var tie = Path()
            tie.addLines([CGPoint(x: 43, y: 63), CGPoint(x: 50, y: 67), CGPoint(x: 43, y: 71)])
            tie.closeSubpath()
            tie.addLines([CGPoint(x: 57, y: 63), CGPoint(x: 50, y: 67), CGPoint(x: 57, y: 71)])
            tie.closeSubpath()
            context.fill(tie.scaled(scale), with: .color(ink))
        case .windmill:
            var body = Path()
            body.addLines([CGPoint(x: 45, y: 48), CGPoint(x: 55, y: 48), CGPoint(x: 60, y: 80), CGPoint(x: 40, y: 80)])
            body.closeSubpath()
            context.fill(body.scaled(scale), with: .color(ink))
            let blade = Path(CGRect(x: 46, y: 18, width: 8, height: 52))
            for degrees: CGFloat in [45, -45] {
                context.fill(blade.rotated(degrees: degrees, around: CGPoint(x: 50, y: 44)).scaled(scale), with: .color(ink))
            }
        case let .text(string, face, size, dy, tracking):
            let text = Text(string)
                .font(.custom(face.postScriptName, fixedSize: size * scale))
                .tracking(tracking * scale)
                .foregroundStyle(ink)
            context.draw(text, at: CGPoint(x: 50 * scale, y: (50 + dy) * scale), anchor: .center)
        case let .ring(radius, width):
            let ring = Path(ellipseIn: CGRect(x: 50 - radius, y: 50 - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring.scaled(scale), with: .color(ink), lineWidth: width * scale)
        case .star:
            context.fill(Self.starPath.scaled(scale), with: .color(ink))
        case .bean:
            let bean = Path(ellipseIn: CGRect(x: 31, y: 24, width: 38, height: 52))
                .applying(CGAffineTransform(translationX: 50, y: 50).rotated(by: 25 * .pi / 180).translatedBy(x: -50, y: -50))
            context.fill(bean.scaled(scale), with: .color(ink))
            var crease = Path()
            crease.move(to: CGPoint(x: 44, y: 28))
            crease.addCurve(to: CGPoint(x: 56, y: 72), control1: CGPoint(x: 58, y: 42), control2: CGPoint(x: 42, y: 58))
            context.stroke(crease.scaled(scale), with: .color(background), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
        case .bottle:
            context.fill(Self.bottlePath.scaled(scale), with: .color(ink))
        case .store:
            var awning = Path()
            awning.addLines([CGPoint(x: 26, y: 40), CGPoint(x: 30, y: 28), CGPoint(x: 70, y: 28), CGPoint(x: 74, y: 40)])
            awning.closeSubpath()
            context.fill(awning.scaled(scale), with: .color(ink))
            var scallop = Path()
            scallop.move(to: CGPoint(x: 26, y: 40))
            for step in 0..<4 {
                let x = 26 + CGFloat(step) * 12
                scallop.addQuadCurve(to: CGPoint(x: x + 12, y: 40), control: CGPoint(x: x + 6, y: 47))
            }
            context.stroke(scallop.scaled(scale), with: .color(ink), lineWidth: 3 * scale)
            let shop = Path(roundedRect: CGRect(x: 31, y: 46, width: 38, height: 26), cornerRadius: 3)
            context.stroke(shop.scaled(scale), with: .color(ink), lineWidth: 4 * scale)
            context.fill(Path(CGRect(x: 45, y: 56, width: 10, height: 16)).scaled(scale), with: .color(ink))
        }
    }

    private static let starPath: Path = {
        var path = Path()
        path.addLines([
            CGPoint(x: 50, y: 33), CGPoint(x: 54.7, y: 44.5), CGPoint(x: 67, y: 45.3), CGPoint(x: 57.6, y: 53.2), CGPoint(x: 60.6, y: 65.2),
            CGPoint(x: 50, y: 58.6), CGPoint(x: 39.4, y: 65.2), CGPoint(x: 42.4, y: 53.2), CGPoint(x: 33, y: 45.3), CGPoint(x: 45.3, y: 44.5),
        ])
        path.closeSubpath()
        return path
    }()

    private static let bottlePath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 45, y: 22))
        path.addLine(to: CGPoint(x: 55, y: 22))
        path.addLine(to: CGPoint(x: 55, y: 34))
        path.addCurve(to: CGPoint(x: 63, y: 50), control1: CGPoint(x: 55, y: 38), control2: CGPoint(x: 63, y: 41))
        path.addLine(to: CGPoint(x: 63, y: 74))
        path.addCurve(to: CGPoint(x: 59, y: 78), control1: CGPoint(x: 63, y: 77), control2: CGPoint(x: 61, y: 78))
        path.addLine(to: CGPoint(x: 41, y: 78))
        path.addCurve(to: CGPoint(x: 37, y: 74), control1: CGPoint(x: 39, y: 78), control2: CGPoint(x: 37, y: 77))
        path.addLine(to: CGPoint(x: 37, y: 50))
        path.addCurve(to: CGPoint(x: 45, y: 34), control1: CGPoint(x: 37, y: 41), control2: CGPoint(x: 45, y: 38))
        path.closeSubpath()
        return path
    }()
}

enum BadgeFace {
    case archivo, anton, pretendardBold, pretendardBlack

    var postScriptName: String {
        switch self {
        case .archivo: return AppFont.numeralName
        case .anton: return "Anton-Regular"
        case .pretendardBold: return AppFont.Weight.bold.postScriptName
        case .pretendardBlack: return AppFont.Weight.black.postScriptName
        }
    }
}

private extension Path {
    func scaled(_ scale: CGFloat) -> Path {
        applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    func rotated(degrees: CGFloat, around center: CGPoint) -> Path {
        applying(CGAffineTransform(translationX: center.x, y: center.y).rotated(by: degrees * .pi / 180).translatedBy(x: -center.x, y: -center.y))
    }
}
