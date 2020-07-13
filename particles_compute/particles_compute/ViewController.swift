//
//  ViewController.swift
//  particles
//
//  Created by Naruki Chigira on 2020/06/12.
//  Copyright © 2020 Naruki Chigira. All rights reserved.
//

import MetalKit
import UIKit

class ViewController: UIViewController {
    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = view as? MTKView else {
            fatalError("Failed get view as MTKView.")
        }
        mtkView = view
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create ssytem default device.")
        }
        view.device = device

        renderer = Renderer(view: view)
        renderer.mtkView(view, drawableSizeWillChange: view.drawableSize)

        // Reference: https://developer.apple.com/documentation/metal/preparing_your_metal_app_to_run_in_the_background
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        guard let view = view as? MTKView else {
            fatalError("Failed get view as MTKView.")
        }
        view.delegate = renderer
    }

    @objc
    private func applicationWillResignActive() {
        mtkView.isPaused = true
    }

    @objc
    private func applicationDidBecomeActive() {
        mtkView.isPaused = false
    }
}

