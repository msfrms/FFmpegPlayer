import AVFoundation
import SwiftFFmpeg

extension AVFrame {
    var nativePixelFormat: OSType {
        switch pixelFormat {
        case .YUVA420P:
            return kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar
        default:
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange        
        }
    }
}
