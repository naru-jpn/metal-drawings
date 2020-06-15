//
//  Renderer.swift
//  particles
//
//  Created by Naruki Chigira on 2020/06/12.
//  Copyright © 2020 Naruki Chigira. All rights reserved.
//

import Foundation
import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
    private static let maxFramesInFlight: Int = 3
    private static let numParticles: Int = 100

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderPipelineState: MTLRenderPipelineState
    let vertexBuffers: [MTLBuffer]

    lazy var particles: [Particle] = (0..<Renderer.numParticles).map { _ in Particle() }

    let inFlightSemaphore = DispatchSemaphore(value: Renderer.maxFramesInFlight)
    var currentBufferIndex: Int = 0

    var viewportSize: vector_uint2 = .zero

    init(view: MTKView) {
        guard let device = view.device else {
            fatalError("Failed to get device from view: \(view)")
        }
        self.device = device

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to make default mtllibrary.")
        }
        guard let vertexFunction = library.makeFunction(name: "particle_vertex"), let fragmentFunction = library.makeFunction(name: "particle_fragment") else {
            fatalError("Failed to make functions.")
        }

        let renderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineStateDescriptor.label = "draw_particles"
        renderPipelineStateDescriptor.sampleCount = view.sampleCount
        renderPipelineStateDescriptor.vertexFunction = vertexFunction
        renderPipelineStateDescriptor.fragmentFunction = fragmentFunction
        renderPipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        renderPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
        renderPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        renderPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        renderPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        renderPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        renderPipelineStateDescriptor.vertexBuffers[0].mutability = .immutable

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineStateDescriptor)
        } catch {
            fatalError("Failed to make render pipeline state with error: \(error)")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to make command queue.")
        }
        self.commandQueue = commandQueue

        let vertexBufferLength: Int = MemoryLayout<vertex_t>.size
        var vertexBuffers: [MTLBuffer] = []
        for i in 0..<Renderer.maxFramesInFlight {
            guard let vertexBuffer = device.makeBuffer(length: vertexBufferLength, options: .storageModeShared) else {
                fatalError("Failed make vertex buffer(\(i).")
            }
            vertexBuffer.label = "vetex_buffer_\(i + 1)"
            vertexBuffers.append(vertexBuffer)
        }
        self.vertexBuffers = vertexBuffers

        super.init()

        for particle in particles {
            particle.applyRandomPosition()
            particle.applyRandomVelocity()
        }
    }

    private func updateState() {
        let currentVertexBuffer = vertexBuffers[currentBufferIndex].contents().bindMemory(to: vertex_t.self, capacity: Renderer.numParticles)
        for (offset, particle) in particles.enumerated() {
            // Update particle position
            particle.position.x += particle.velocity.x
            particle.position.y += particle.velocity.y

            currentVertexBuffer[offset].position.x = Float(particle.position.x)
            currentVertexBuffer[offset].position.y = Float(particle.position.y)

            // Update particle velocity
            let r2 = max(5.0E5, pow(particle.position.x, 2) + pow(particle.position.y, 2))
            let r = sqrt(r2)
            particle.velocity.x -= 1.0E5 * (particle.position.x / r) / r2
            particle.velocity.y -= 1.0E5 * (particle.position.y / r) / r2
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)
    }

    func draw(in view: MTKView) {
        let semaphore = inFlightSemaphore
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)

        currentBufferIndex = (currentBufferIndex + 1) % Renderer.maxFramesInFlight

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to make command buffer.")
        }

        updateState()

        guard let renderPassDescriptor = view.currentRenderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        renderEncoder.label = "Primary Render Encoder"

        renderEncoder.pushDebugGroup("Draw Particles")
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffers[currentBufferIndex], offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<vector_uint2>.size, index: 1)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Renderer.numParticles)
        renderEncoder.popDebugGroup()

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }
        commandBuffer.commit()
    }
}
