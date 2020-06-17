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
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create ssytem default device.")
        }
        view.device = device
//        view.clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)

        renderer = Renderer(view: view)
        renderer.mtkView(view, drawableSizeWillChange: view.drawableSize)
    }

    override func viewDidAppear(_ animated: Bool) {
        guard let view = view as? MTKView else {
            fatalError("Failed get view as MTKView.")
        }
        view.delegate = renderer
    }
}

