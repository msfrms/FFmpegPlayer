import UIKit
import AVFoundation

extension CIImage {
    var uiImage: UIImage {
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(self, from: extent)!
        let image = UIImage(cgImage: cgImage)
        return image
    }
}

extension CMSampleBuffer {
    var image: UIImage {
        let imageBuffer = CMSampleBufferGetImageBuffer(self)!
        let ciimage = CIImage(cvPixelBuffer: imageBuffer)
        return ciimage.uiImage
    }
}

class ViewController: UIViewController {
    
    let imageView = UIImageView()
    let videoDemuxer = FFMpegVideoDemuxer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let url = Bundle.main.url(forResource: "segment_04", withExtension: "ts") else {
            fatalError()
        }
        
        guard let filePath = FilePath(url: url) else {
            fatalError()
        }
        
        DispatchQueue.global().async {
            let buffers = (try? self.videoDemuxer.demux(from: filePath)) ?? []
            let images = buffers.map { $0.image }
            
            DispatchQueue.main.async {
                self.imageView.animationImages = images
                self.imageView.startAnimating()
            }
        }
        // needs rewritten to AVSampleBufferDisplayLayer
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFill
        imageView.animationDuration = 5
        imageView.animationRepeatCount = 10
        imageView.backgroundColor = .red
        
        view.addSubview(imageView)
    }

}

