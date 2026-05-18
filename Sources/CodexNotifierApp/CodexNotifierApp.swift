import AppKit
import CodexNotifierCore
import SwiftUI

@main
struct CodexNotifierApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            Text(controller.recentEventSummary)
            Text(controller.channelStatusSummary)
            Divider()
            Button("설정") {
                controller.openSettingsWindow()
            }
            Button("로그 보기") {
                controller.openLogs()
            }
            Divider()
            Button("종료") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(nsImage: MenuBarStatusIconImage.make(for: controller.statusIconState))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(controller: controller)
                .frame(width: 780, height: 620)
        }
    }
}
