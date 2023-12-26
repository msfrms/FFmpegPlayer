import SwiftFFmpeg
import AVFoundation

extension AVStream {
    var codec: AVCodec? {
        AVCodec.findDecoderById(codecParameters.codecId)
    }
    
    var codecContext: AVCodecContext {
        AVCodecContext(codec: codec)
    }
    
    var nativeTimebase: CMTime {
        var timebase: CMTime
        
        let context = codecContext
        
        if self.timebase != .zero {
            timebase = self.timebase.time
        } else if context.timebase != .zero {
            timebase = context.timebase.time
        } else {
            timebase = CMTimeMake(value: 1, timescale: 40_000)
        }
        
        return timebase
    }
}
