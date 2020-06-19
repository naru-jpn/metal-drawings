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
    private static let numParticles: Int = 200
    private static let defaultTextureSize: CGSize = CGSize(width: 1024, height: 1024)

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    let particleRenderPipelineState: MTLRenderPipelineState
    let thresholdRenderPipelineState: MTLRenderPipelineState

    let particleVertexBuffers: [MTLBuffer]
    let thresholdVertexBuffer: MTLBuffer

    let textureDescriptor: MTLTextureDescriptor
    var particleTexture: MTLTexture

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

        // particleRenderPipelineState

        guard let particleVertexFunction = library.makeFunction(name: "particle_vertex"), let particleFragmentFunction = library.makeFunction(name: "particle_fragment") else {
            fatalError("Failed to make functions.")
        }

        let particleRenderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        particleRenderPipelineStateDescriptor.label = "draw_particles"
        particleRenderPipelineStateDescriptor.sampleCount = view.sampleCount
        particleRenderPipelineStateDescriptor.vertexFunction = particleVertexFunction
        particleRenderPipelineStateDescriptor.fragmentFunction = particleFragmentFunction
        particleRenderPipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        particleRenderPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        particleRenderPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
        particleRenderPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        particleRenderPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        particleRenderPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleRenderPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        particleRenderPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        particleRenderPipelineStateDescriptor.vertexBuffers[0].mutability = .immutable

        do {
            particleRenderPipelineState = try device.makeRenderPipelineState(descriptor: particleRenderPipelineStateDescriptor)
        } catch {
            fatalError("Failed to make particle render pipeline state with error: \(error)")
        }

        // thresholdRenderPipelineState

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<float_t>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[0].stride = MemoryLayout<float_t>.size * 4

        guard let thresholdVertexFunction = library.makeFunction(name: "threshold_vertex"), let thresholdFragmentFunction = library.makeFunction(name: "threshold_fragment") else {
            fatalError("Failed to make functions.")
        }

        let thresholdRenderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        thresholdRenderPipelineStateDescriptor.label = "threshold_filter"
        thresholdRenderPipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        thresholdRenderPipelineStateDescriptor.vertexFunction = thresholdVertexFunction
        thresholdRenderPipelineStateDescriptor.fragmentFunction = thresholdFragmentFunction
        thresholdRenderPipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        do {
            thresholdRenderPipelineState = try device.makeRenderPipelineState(descriptor: thresholdRenderPipelineStateDescriptor)
        } catch {
            fatalError("Failed to make threshold render pipeline state with error: \(error)")
        }

        // commandQueue

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to make command queue.")
        }
        self.commandQueue = commandQueue

        // buffers

        let vertexBufferLength: Int = MemoryLayout<vertex_t>.size * Renderer.numParticles
        var vertexBuffers: [MTLBuffer] = []
        for i in 0..<Renderer.maxFramesInFlight {
            guard let vertexBuffer = device.makeBuffer(length: vertexBufferLength, options: .storageModeShared) else {
                fatalError("Failed make vertex buffer(\(i)).")
            }
            vertexBuffer.label = "vetex_buffer_\(i + 1)"
            vertexBuffers.append(vertexBuffer)
        }
        self.particleVertexBuffers = vertexBuffers

        let bytes: [float_t] = [
            -1.0, -1.0,  0.0,  1.0,
             1.0, -1.0,  1.0,  1.0,
            -1.0,  1.0,  0.0,  0.0,
             1.0,  1.0,  1.0,  0.0,
        ]
        guard let buffer = device.makeBuffer(bytes: bytes, length: MemoryLayout<float_t>.size * bytes.count, options: .optionCPUCacheModeWriteCombined) else {
            fatalError("Failed make buffer.")
        }
        thresholdVertexBuffer = buffer

        // textures

        textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.pixelFormat = view.colorPixelFormat
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.width = Int(Renderer.defaultTextureSize.width)
        textureDescriptor.height = Int(Renderer.defaultTextureSize.height)

        guard let particleTexture = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError("Failed to make particle texture.")
        }
        self.particleTexture = particleTexture

        super.init()

        for particle in particles {
            particle.applyRandomPosition()
            particle.applyRandomVelocity()
        }
    }

    private func updateState() {
        let currentVertexBuffer = particleVertexBuffers[currentBufferIndex].contents().bindMemory(to: vertex_t.self, capacity: Renderer.numParticles)
        for (offset, particle) in particles.enumerated() {
            // Update particle position
            particle.position.x += particle.velocity.x
            particle.position.y += particle.velocity.y

            currentVertexBuffer[offset].position.x = Float(particle.position.x)
            currentVertexBuffer[offset].position.y = Float(particle.position.y)

            // Update particle velocity
            let r2 = max(5.0E5, pow(particle.position.x, 2) + pow(particle.position.y, 2))
            particle.velocity.x -= 1.0E5 * (particle.position.x / abs(particle.position.x)) / r2
            particle.velocity.y -= 1.0E5 * (particle.position.y / abs(particle.position.y)) / r2
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)

        textureDescriptor.width = Int(size.width)
        textureDescriptor.height = Int(size.height)
        guard let particleTexture = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError("Failed to make particle texture.")
        }
        self.particleTexture = particleTexture
    }

    func draw(in view: MTKView) {
        let semaphore = inFlightSemaphore
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)

        currentBufferIndex = (currentBufferIndex + 1) % Renderer.maxFramesInFlight

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to make command buffer.")
        }

        updateState()

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = particleTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        renderEncoder.label = "Particle Render Encoder"

        renderEncoder.pushDebugGroup("Draw Particles")
        renderEncoder.setRenderPipelineState(particleRenderPipelineState)
        renderEncoder.setVertexBuffer(particleVertexBuffers[currentBufferIndex], offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<vector_uint2>.size, index: 1)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Renderer.numParticles)
        renderEncoder.popDebugGroup()

        renderEncoder.endEncoding()


        renderPassDescriptor.colorAttachments[0].texture = view.currentDrawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        renderEncoder = encoder
        renderEncoder.label = "Threshold Render Encoder"

        renderEncoder.pushDebugGroup("Threshold Filter")
        renderEncoder.setRenderPipelineState(thresholdRenderPipelineState)
        renderEncoder.setVertexBuffer(thresholdVertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(particleTexture, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
