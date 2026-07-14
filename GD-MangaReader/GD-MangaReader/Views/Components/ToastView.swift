import SwiftUI

/// トースト通知のデータ
struct ToastData: Equatable {
    enum ToastType {
        case success
        case error
        case info
        case warning
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return .appSuccess
            case .error: return .appDestructive
            case .info: return .accentColor
            case .warning: return .appWarning
            }
        }
    }
    
    let title: String
    let message: String
    let type: ToastType
}

/// トースト通知を表示するビュー
struct ToastView: View {
    let data: ToastData
    let onDismiss: () -> Void
    @State private var dismissTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: data.type.icon)
                    .foregroundColor(data.type.color)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(data.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    onDismiss()
                }
            }
        }
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
        .onTapGesture {
            dismissTask?.cancel()
            onDismiss()
        }
    }
}

/// トースト表示用モディファイア
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let data = toast {
                ToastView(data: data) {
                    withAnimation {
                        toast = nil
                    }
                }
            }
        }
    }
}

extension View {
    /// トースト通知を表示する
    func toastView(toast: Binding<ToastData?>) -> some View {
        self.modifier(ToastModifier(toast: toast))
    }
}
