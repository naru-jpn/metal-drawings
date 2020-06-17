//
//  Particle.swift
//  particles
//
//  Created by Naruki Chigira on 2020/06/16.
//  Copyright © 2020 Naruki Chigira. All rights reserved.
//

import UIKit

class Particle {
    var position: CGPoint = .zero
    var velocity: CGPoint = .zero
}

extension Particle {
    func applyRandomPosition() {
        position.x = CGFloat.random(in: -200...200)
        position.y = CGFloat.random(in: -200...200)
    }

    func applyRandomVelocity() {
        velocity.x = CGFloat.random(in: -8...8)
        velocity.y = CGFloat.random(in: -13...13)
    }
}
