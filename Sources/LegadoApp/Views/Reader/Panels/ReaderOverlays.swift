import SwiftUI
#if canImport(LegadoCore)
import LegadoCore
#endif

/// A 3×3 grid of configurable tap zones, mirroring Android `ReadView.setRect9x()`.
///
/// Only used by the paged reader. Overlaying this on the scrolling reader would steal the
/// touches the `ScrollView` needs, so scroll mode keeps a single centre-zone tap.
struct TapZoneOverlay: View {
    let actions: [ClickActionCode]
    let onAction: (ClickActionCode) -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            Color.clear
                                .frame(width: geo.size.width / 3, height: geo.size.height / 3)
                                .contentShape(Rectangle())
                                .onTapGesture { onAction(actions[index]) }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
