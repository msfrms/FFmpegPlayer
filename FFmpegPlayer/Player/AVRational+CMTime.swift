import SwiftFFmpeg
import AVFoundation

extension AVRational {
    static var zero: Self {
        .init(num: 0, den: 0)
    }
    
    var time: CMTime {
        CMTime(value: CMTimeValue(num), timescale: den)
    }
}
