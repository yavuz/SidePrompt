import SwiftUI

struct PanelRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack(alignment: .top) {
            QueueView()

            if let toast = appModel.toastMessage {
                ToastBanner(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 14)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: appModel.toastMessage)
        .frame(minWidth: 320, minHeight: 420)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ToastBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
