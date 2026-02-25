// ShimmerModifier.swift
// GD-MangaReader

import SwiftUI

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    private let duration: Double = 1.5
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    Color.white
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.5), location: 0.5),
                                    .init(color: .clear, location: 1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width * 3) // 十分な幅を取る
                            .offset(x: -geometry.size.width + (geometry.size.width * 2) * phase)
                        )
                }
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// ビューにShimmer（骨組み表示用のアニメーション）効果を付与する
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}
