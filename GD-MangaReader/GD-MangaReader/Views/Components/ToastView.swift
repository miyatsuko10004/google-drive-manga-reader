import SwiftUI

/// トーストのアクションボタン（最大1つ。後続ステップの「元に戻す」等に使う）
struct ToastAction {
    let label: String
    let handler: () -> Void
}

/// トースト通知のデータ
struct ToastData {
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
    /// 任意のアクション（最大1つ）。実行するとトーストは閉じる
    var action: ToastAction? = nil
}

/// トースト通知のカードビュー。
/// 表示タイミング（3秒自動消去・置き換え）は StatusCenter が管理し、
/// このビューはカードの見た目とタップ/アクションによる消去のみを担う。
struct ToastView: View {
    let data: ToastData
    let onDismiss: () -> Void

    var body: some View {
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

            if let action = data.action {
                Button {
                    // 先に自トーストを閉じてからアクションを実行する。
                    // ハンドラーが後続トースト（例: 「元に戻す」の結果報告）を表示するケースで、
                    // 後から呼ばれるdismissが新しいトーストを消してしまわないようにするため
                    onDismiss()
                    action.handler()
                } label: {
                    Text(action.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
    }
}
