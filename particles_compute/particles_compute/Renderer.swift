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
    private static let maxFramesInSimulate: Int = 1
    private static let numParticles: Int = 100
    private static let defaultTextureSize: CGSize = CGSize(width: 1024, height: 1024)

    let view: MTKView
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    let particleTexture: MTLTexture

    let simulatePipelineState: MTLComputePipelineState
    let particleRenderPipelineState: MTLRenderPipelineState
    let thresholdRenderPipelineState: MTLRenderPipelineState

    let particleBuffers: [MTLBuffer]
    let thresholdVertexBuffer: MTLBuffer

    let textureDescriptor: MTLTextureDescriptor
    var textures: [MTLTexture]

    lazy var particles: [Particle] = (0..<Renderer.numParticles).map { _ in Particle() }

    let inFlightSemaphore = DispatchSemaphore(value: Renderer.maxFramesInFlight)
    let inSimulateSemaphore = DispatchSemaphore(value: Renderer.maxFramesInSimulate)
    var currentBufferIndex: Int = 0

    var viewportSize: vector_uint2 = .zero
    var numParticles: uint = uint(Renderer.numParticles)

    init(view: MTKView) {
        self.view = view
        guard let device = view.device else {
            fatalError("Failed to get device from view: \(view)")
        }
        self.device = device

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to make default mtllibrary.")
        }

        // simulatePipelineState

        guard let simulationFunction = library.makeFunction(name: "simulation") else {
            fatalError("Failed to make functions.")
        }
        do {
            simulatePipelineState = try device.makeComputePipelineState(function: simulationFunction)
        } catch {
            fatalError("Failed to make simutate pipeline state with error: \(error)")
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

        let vertexBufferLength: Int = MemoryLayout<particle_t>.size * Renderer.numParticles
        var vertexBuffers: [MTLBuffer] = []
        for i in 0..<Renderer.maxFramesInFlight {
            guard let vertexBuffer = device.makeBuffer(length: vertexBufferLength, options: .storageModeShared) else {
                fatalError("Failed make vertex buffer(\(i)).")
            }
            vertexBuffer.label = "vetex_buffer_\(i + 1)"
            vertexBuffers.append(vertexBuffer)
        }
        self.particleBuffers = vertexBuffers

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

        let textureLoader = MTKTextureLoader(device: device)
        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue),
            MTKTextureLoader.Option.generateMipmaps: NSNumber(value: true)
        ]
        particleTexture = try! textureLoader.newTexture(name: "particle", scaleFactor: 1.0, bundle: nil, options: textureLoaderOptions)

        textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.pixelFormat = view.colorPixelFormat
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.width = Int(Renderer.defaultTextureSize.width)
        textureDescriptor.height = Int(Renderer.defaultTextureSize.height)

        var textures: [MTLTexture] = []
        for _ in 0..<Renderer.maxFramesInFlight {
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                fatalError("Failed to make particle texture.")
            }
            textures.append(texture)
        }
        self.textures = textures

        super.init()

        for particle in particles {
            particle.applyRandomPosition()
            particle.applyRandomVelocity()
        }
        let particleBuffer = particleBuffers[0].contents().bindMemory(to: particle_t.self, capacity: Renderer.numParticles)
        for (offset, particle) in particles.enumerated() {
            particleBuffer[offset].position = vector_float2(x: Float(particle.position.x), y: Float(particle.position.y))
            particleBuffer[offset].velocity = vector_float2(x: Float(particle.velocity.x), y: Float(particle.velocity.y))
        }
    }

    private func updateState(with commandBuffer: MTLCommandBuffer) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        computeEncoder.label = "Simulation Encoder"

        let dispatchThreads = MTLSize(width: Renderer.numParticles, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: simulatePipelineState.threadExecutionWidth, height: 1, depth: 1)

        computeEncoder.setComputePipelineState(simulatePipelineState)
        computeEncoder.setBuffer(particleBuffers[currentBufferIndex], offset: 0, index: 0)
        computeEncoder.setBuffer(particleBuffers[(currentBufferIndex + 1) % Renderer.maxFramesInFlight], offset: 0, index: 1)
        computeEncoder.setBytes(&numParticles, length: MemoryLayout<uint>.size, index: 2)
        computeEncoder.setThreadgroupMemoryLength(simulatePipelineState.threadExecutionWidth * MemoryLayout<particle_t>.size, index: 0)
        computeEncoder.dispatchThreads(dispatchThreads, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
    }

    private func render(with commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = textures[currentBufferIndex]
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        renderEncoder.label = "Particle Render Encoder"

        renderEncoder.pushDebugGroup("Draw Particles")
        renderEncoder.setRenderPipelineState(particleRenderPipelineState)
        renderEncoder.setVertexBuffer(particleBuffers[(currentBufferIndex + 1) % Renderer.maxFramesInFlight], offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<vector_float2>.size, index: 1)
        renderEncoder.setFragmentTexture(particleTexture, index: 0)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Renderer.numParticles)
        renderEncoder.popDebugGroup()

        renderEncoder.endEncoding()

        renderPassDescriptor.colorAttachments[0].texture = view.currentDrawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let currentRenderPassDescriptor = view.currentRenderPassDescriptor, let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor) else {
            return
        }
        renderEncoder = encoder
        renderEncoder.label = "Threshold Render Encoder"

        renderEncoder.pushDebugGroup("Threshold Filter")
        renderEncoder.setRenderPipelineState(thresholdRenderPipelineState)
        renderEncoder.setVertexBuffer(thresholdVertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(textures[currentBufferIndex], index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.popDebugGroup()

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
    }

    func draw(in view: MTKView) {
        let semaphore = inFlightSemaphore
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)

        // Simulate
        do {
            let simulateSemaphore = inSimulateSemaphore
            _ = simulateSemaphore.wait(timeout: DispatchTime.distantFuture)

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                fatalError("Failed to make command buffer.")
            }
            updateState(with: commandBuffer)
            commandBuffer.addCompletedHandler { _ in
                simulateSemaphore.signal()
            }
            commandBuffer.commit()
        }

        // Render
        do {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                fatalError("Failed to make command buffer.")
            }
            render(with: commandBuffer)
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }
            commandBuffer.commit()
        }

        currentBufferIndex = (currentBufferIndex + 1) % Renderer.maxFramesInFlight
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)

        textureDescriptor.width = Int(size.width)
        textureDescriptor.height = Int(size.height)
        var textures: [MTLTexture] = []
        for _ in 0..<Renderer.maxFramesInFlight {
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                fatalError("Failed to make particle texture.")
            }
            textures.append(texture)
        }
        self.textures = textures
    }
}
