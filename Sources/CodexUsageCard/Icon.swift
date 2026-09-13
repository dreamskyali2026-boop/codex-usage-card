import SwiftUI
import AppKit

enum IconRenderer {
    @MainActor
    static func render(to path: String) {
        let renderer = ImageRenderer(content: IconArtwork().frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { exit(1) }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch { exit(1) }
    }
}

struct IconArtwork: View {
    private let corner: CGFloat = 232

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.12, blue: 0.28),
                            Color(red: 0.23, green: 0.15, blue: 0.44),
                            Color(red: 0.09, green: 0.21, blue: 0.40),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Ellipse()
                .fill(Color(red: 0.35, green: 0.90, blue: 0.70).opacity(0.55))
                .frame(width: 620, height: 420)
                .blur(radius: 150)
                .offset(x: 190, y: -140)

            Ellipse()
                .fill(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.50))
                .frame(width: 560, height: 460)
                .blur(radius: 160)
                .offset(x: -210, y: 210)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 84)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.45, green: 0.95, blue: 0.65),
                                Color(red: 0.30, green: 0.85, blue: 0.85),
                                Color(red: 0.45, green: 0.95, blue: 0.65).opacity(0.7),
                            ],
                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 84, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(red: 0.40, green: 0.95, blue: 0.70).opacity(0.75), radius: 42)

                Image(systemName: "hourglass")
                    .font(.system(size: 288, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .frame(width: 560, height: 560)

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.0)],
                        startPoint: .top, endPoint: .center
                    )
                )

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .padding(0)
    }
}
