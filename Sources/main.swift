import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        let contentView = ContentView()
        
        // 创建唯一的小型标准悬浮窗：带标准的红黄绿关闭/最小化按钮，与窗口内容一体化
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        win.title = "Mini Transcribe"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.level = .floating // 始终置顶浮窗
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isMovableByWindowBackground = true // 点击空白处即可随意拖拽
        win.center()
        win.contentView = NSHostingView(rootView: contentView)
        win.delegate = self
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        // 关闭小窗口直接退出程序
        NSApp.terminate(nil)
    }
}

// 纯 AppKit 启动入口，彻底杜绝 SwiftUI 默认弹出的空白大窗口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
