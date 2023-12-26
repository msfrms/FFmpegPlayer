import AVFoundation
import SwiftFFmpeg

public final class FFMpegVideoDemuxer: Demuxer {
    enum FFMpegErrors: Error {
        case notFoundVideoStream
        case notFoundVideoCodec
    }
    
    private let decoder = FFMpegVideoDecoder()
    
    public init() {}
    
    public func demux(from file: FilePath) throws -> [CMSampleBuffer] {
        let formatContext = try AVFormatContext(url: file.path.absoluteString)
        try formatContext.findStreamInfo()
        
        let stream = formatContext.streams.first { $0.mediaType == .video }
        
        guard let videoStream = stream else {
            throw FFMpegErrors.notFoundVideoStream
        }
        
        guard videoStream.codec != nil else {
            throw FFMpegErrors.notFoundVideoCodec
        }

        let videoCodecContext = videoStream.codecContext
        videoCodecContext.setParameters(videoStream.codecParameters)
        
        try videoCodecContext.openCodec()

        let packet = AVPacket()
        let frame = AVFrame()
        
        var buffers: [CMSampleBuffer] = []
        
        while let _ = try? formatContext.readFrame(into: packet) {
            defer { packet.unref() }
            
            guard packet.streamIndex == videoStream.index else {
                continue
            }

            try videoCodecContext.sendPacket(packet)
            
            while true {
                                
                do {
                    try videoCodecContext.receiveFrame(frame)
                    
                } catch let error as SwiftFFmpeg.AVError where error == .tryAgain || error == .eof {
                    frame.unref()
                    break
                }
                
                let sampleBuffer = try decoder.decode(
                    frame: frame,
                    timebase: videoStream.nativeTimebase
                )
                
                buffers.append(sampleBuffer)
                
                frame.unref()
            }
        }
        
        return buffers
    }
}
