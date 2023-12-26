import Foundation

public struct FilePath {
    let path: URL
    
    public init?(url: URL) {
        guard url.isFileURL else {
            return nil
        }
        
        path = url
    }
}
