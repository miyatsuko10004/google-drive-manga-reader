// ToastView.swift
// GD-MangaReader

import SwiftUI

struct ToastData: Equatable {
    let title: String
    let message: String?
    let type: ToastType
}

enum ToastType {
    case info
    case success
    case error
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?
    @State private var task: Task<Void, Swift.Error>?
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                ZStack {
                    mainToastView()
                }
                .animation(.spring(), value: toast)
            )
            .onChange(of: toast) { _, newValue in
                showToast()
            }
            .onDisappear {
                task?.cancel()
                task = nil
            }
    }
    
    @ViewBuilder
    func mainToastView() -> some View {
        if let toast = toast {
            VStack {
                Spacer() // 上部に出すか下部に出すかで調整。今回は下部に出す
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: toast.type.icon)
                        .foregroundColor(toast.type.color)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if let message = toast.message {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer(minLength: 10)
                    
                    Button {
                        dismissToast()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground).opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                .padding(.horizontal, 20)
                .padding(.bottom, 30) // フッター等との被りを避ける
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .zIndex(100)
        }
    }
    
    private func showToast() {
        guard toast != nil else { return }
        
        task?.cancel()
        
        task = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissToast()
            }
        }
    }
    
    private func dismissToast() {
        withAnimation(.spring()) {
            toast = nil
        }
        
        task?.cancel()
        task = nil
    }
}

extension View {
    func toastView(toast: Binding<ToastData?>) -> some View {
        self.modifier(ToastModifier(toast: toast))
    }
}
