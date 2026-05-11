import SwiftUI

// MARK: - NSVisualEffectView 封装

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - 毛玻璃背景修饰器

struct GlassBackgroundModifier: ViewModifier {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func body(content: Content) -> some View {
        content
            .background(
                VisualEffectView(material: material, blendingMode: blendingMode)
            )
    }
}

// MARK: - 卡片毛玻璃修饰器

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - View 扩展

extension View {
    /// 全窗口毛玻璃背景
    func glassBackground(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) -> some View {
        modifier(GlassBackgroundModifier(material: material, blendingMode: blendingMode))
    }

    /// 卡片样式毛玻璃
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
