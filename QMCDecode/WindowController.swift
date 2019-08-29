//
//  WindowController.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2019/8/26.
//  Copyright © 2019 龚杰洪. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()
    
        self.window?.delegate = WindowDelegate.default
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    static let `default`: WindowDelegate = {
        return WindowDelegate()
    }()
    
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(self)
    }
}
