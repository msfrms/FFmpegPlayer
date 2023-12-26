import AVFoundation

public protocol Demuxer {
    func demux(from path: FilePath) throws -> [CMSampleBuffer]
}
