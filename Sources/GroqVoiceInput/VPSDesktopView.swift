import SwiftUI

struct VPSDesktopView: View {
    @ObservedObject var panel: VPSDesktopPanel
    @ObservedObject var connection: VPSDesktopConnection
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VPS 遠端桌面").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { panel.toggle?() } label: { Image(systemName: panel.collapsed ? "chevron.down" : "chevron.up").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel(panel.collapsed ? "展開 VPS 面板" : "收合 VPS 面板")
            }.padding(.leading, 80).padding(.trailing, 14).frame(height: 48)
            if !panel.collapsed {
                Divider().opacity(0.45)
                HStack(spacing: 7) {
                    Circle().fill(connection.connected ? Color(hex: 0x75977D) : Color(hex: 0xBDA1AA)).frame(width: 6, height: 6)
                    Text(connection.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { connection.connect() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("重新連線 VPS").accessibilityLabel("重新連線 VPS").disabled(connection.loading || connection.awaitingCredentials || connection.connected)
                }.padding(.horizontal, 16).padding(.vertical, 10)
                ZStack {
                    VPSDesktopSurface(connection: connection)
                    if !connection.connected && !connection.loading && !connection.awaitingCredentials {
                        VStack(spacing: 14) {
                            Image(systemName: "display").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text(connection.status).font(.system(size: 13, weight: .medium))
                            Text("按下重新連線，再輸入 VNC 密碼即可。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("重新連線並登入") { connection.connect() }.buttonStyle(.borderedProminent)
                                .accessibilityLabel("重新連線並登入")
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: 0xFAF8F9))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                HStack(spacing: 10) {
                    Label("VPS 電腦", systemImage: "desktopcomputer").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if connection.connected {
                        Button(connection.controlling ? "結束接手" : "接手操作") { connection.toggleControl() }.font(.system(size: 11)).accessibilityLabel(connection.controlling ? "結束接手" : "接手操作")
                        Button("中斷") { connection.confirmDisconnect = true }.font(.system(size: 11)).accessibilityLabel("中斷 VPS 連線")
                    } else {
                        Text(connection.awaitingCredentials ? "先完成上方密碼登入" : "連線完成後才可接手操作")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.bordered).padding(12)
            }
        }.background(Color.white).preferredColorScheme(.light).ignoresSafeArea()
        .alert("確定中斷 VPS 連線？", isPresented: $connection.confirmDisconnect) {
            Button("繼續連線", role: .cancel) {}
            Button("中斷連線", role: .destructive) { connection.disconnect() }
        } message: {
            Text("只是想暫時收起視窗，請使用右上角收合按鈕，連線會保留。")
        }
    }
}

final class VPSDesktopPanel: ObservableObject {
    @Published var collapsed = false
    var toggle: (() -> Void)?
}

private extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
