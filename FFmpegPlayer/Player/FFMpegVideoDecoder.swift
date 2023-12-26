import AVFoundation
import SwiftFFmpeg
import Accelerate

final class FFMpegVideoDecoder {
    enum VideoDecoderError: Error {
        case invalidFrame
        case avFoundationErrorCode(Int32)
    }
    
    private var uvPlane: (UnsafeMutablePointer<UInt8>, Int)?
    
    private func fillDstPlane(dstPlane: UnsafeMutablePointer<UInt8>,
                              srcPlane1: UnsafeMutablePointer<UInt8>,
                              srcPlane2: UnsafeMutablePointer<UInt8>,
                              srcPlaneSize: Int) {
        let ranges = 0..<srcPlaneSize
        
        for i in ranges {
            dstPlane[2 * i] = srcPlane1[i]
            dstPlane[2 * i + 1] = srcPlane2[i]
        }
    }
    
    func decode(frame: AVFrame, timebase: CMTime) throws -> CMSampleBuffer {
        guard frame.data[0] != nil else {
            throw VideoDecoderError.invalidFrame
        }
        
        guard frame.linesize[1] == frame.linesize[2] else {
            throw VideoDecoderError.invalidFrame
        }
        
        var pixelBuffer: CVPixelBuffer?
        
        let pts = CMTimeMake(value: frame.pts, timescale: timebase.timescale)
        let dts = CMTime(value: frame.dts, timescale: timebase.timescale)
        
        let pixelFormat: OSType = frame.nativePixelFormat
        
        let options: [String: Any] = [kCVPixelBufferBytesPerRowAlignmentKey as String: frame.linesize[0] as NSNumber]
        
        let createdPixelBufferCode = CVPixelBufferCreate(kCFAllocatorDefault,
                                                         Int(frame.width),
                                                         Int(frame.height),
                                                         pixelFormat,
                                                         options as CFDictionary,
                                                         &pixelBuffer)
        
        guard let pixelBuffer, createdPixelBufferCode == kCVReturnSuccess else {
            throw VideoDecoderError.avFoundationErrorCode(createdPixelBufferCode)
        }
        
        let pixelBufferLockAddressResult = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        guard pixelBufferLockAddressResult == kCVReturnSuccess else {
            throw VideoDecoderError.avFoundationErrorCode(pixelBufferLockAddressResult)
        }
        
        var base: UnsafeMutableRawPointer
        
        let srcPlaneSize = Int(frame.linesize[1]) * Int(frame.height / 2)
        let uvPlaneSize = srcPlaneSize * 2
        
        let uvPlane: UnsafeMutablePointer<UInt8>
        
        if let (existingUvPlane, existingUvPlaneSize) = self.uvPlane, existingUvPlaneSize == uvPlaneSize {
            uvPlane = existingUvPlane
        } else {
            if let (existingDstPlane, _) = self.uvPlane {
                free(existingDstPlane)
            }
            uvPlane = malloc(uvPlaneSize)!.assumingMemoryBound(to: UInt8.self)
            self.uvPlane = (uvPlane, uvPlaneSize)
        }
        
        fillDstPlane(
            dstPlane: uvPlane,
            srcPlane1: frame.data[1]!,
            srcPlane2: frame.data[2]!,
            srcPlaneSize: srcPlaneSize
        )
        
        let bytesPerRowY = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytesPerRowUV = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let bytesPerRowA = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 2)
        
        var requiresAlphaMultiplication = false
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar {
            requiresAlphaMultiplication = true
            
            base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2)!
            if bytesPerRowA == frame.linesize[3] {
                memcpy(base, frame.data[3]!, bytesPerRowA * Int(frame.height))
            } else {
                var dest = base
                var src = frame.data[3]!
                let lineSize = Int(frame.linesize[3])
                for _ in 0 ..< Int(frame.height) {
                    memcpy(dest, src, lineSize)
                    dest = dest.advanced(by: bytesPerRowA)
                    src = src.advanced(by: lineSize)
                }
            }
        }
        
        base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
        
        if bytesPerRowY == frame.linesize[0] {
            memcpy(base, frame.data[0]!, bytesPerRowY * Int(frame.height))
        } else {
            var dest = base
            var src = frame.data[0]!
            let lineSize = Int(frame.linesize[0])
            for _ in 0 ..< Int(frame.height) {
                memcpy(dest, src, lineSize)
                dest = dest.advanced(by: bytesPerRowY)
                src = src.advanced(by: lineSize)
            }
        }
        
        if requiresAlphaMultiplication {
            var y = vImage_Buffer(
                data: CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!,
                height: vImagePixelCount(frame.height),
                width: vImagePixelCount(bytesPerRowY),
                rowBytes: bytesPerRowY
            )
            var a = vImage_Buffer(
                data: CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2)!,
                height: vImagePixelCount(frame.height),
                width: vImagePixelCount(bytesPerRowY),
                rowBytes: bytesPerRowA
            )
            let _ = vImagePremultiplyData_Planar8(&y, &a, &y, vImage_Flags(kvImageDoNotTile))
        }
        
        base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
        
        if bytesPerRowUV == frame.linesize[1] * 2 {
            memcpy(base, uvPlane, Int(frame.height / 2) * bytesPerRowUV)
        } else {
            var dest = base
            var src = uvPlane
            let lineSize = Int(frame.linesize[1]) * 2
            for _ in 0 ..< Int(frame.height / 2) {
                memcpy(dest, src, lineSize)
                dest = dest.advanced(by: bytesPerRowUV)
                src = src.advanced(by: lineSize)
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        var formatRef: CMVideoFormatDescription?
        
        let createdVideoFormatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatRef
        )
        
        guard let formatDescription: CMVideoFormatDescription = formatRef,
                createdVideoFormatStatus == noErr else {
            throw VideoDecoderError.avFoundationErrorCode(createdVideoFormatStatus)
        }
        
        var timingInfo: CMSampleTimingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )
        var newSampleBuffer: CMSampleBuffer?
        
        let createSampleBufferStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer)
        
        guard createSampleBufferStatus == noErr, let newSampleBuffer else {
            throw VideoDecoderError.avFoundationErrorCode(createdPixelBufferCode)
        }
        
        return newSampleBuffer
    }
}
