import Foundation
import AppKit

public class UpdaterService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = UpdaterService()
    
    @Published public var isChecking = false
    @Published public var updateAvailable = false
    @Published public var currentVersion: String = ""
    @Published public var latestVersion: String = ""
    @Published public var releaseNotes: String = ""
    @Published public var downloadProgress: Double = 0.0
    @Published public var isDownloading = false
    @Published public var errorMessage: String? = nil
    
    private var downloadUrl: String? = nil
    
    private override init() {
        super.init()
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = version
        } else {
            self.currentVersion = "1.0.0"
        }
    }
    
    public func checkForUpdates() {
        guard !isChecking && !isDownloading else { return }
        isChecking = true
        errorMessage = nil
        updateAvailable = false
        
        let url = URL(string: "https://api.github.com/repos/Varun-Chinthoju/Airspace/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("Airspace-Updater", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                if let error = error {
                    self?.errorMessage = "Error checking for updates: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "Failed to retrieve update information."
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let tagName = json["tag_name"] as? String,
                           let body = json["body"] as? String,
                           let assets = json["assets"] as? [[String: Any]] {
                            
                            let cleanedLatest = tagName.replacingOccurrences(of: "v", with: "")
                            self?.latestVersion = cleanedLatest
                            self?.releaseNotes = body
                            
                            let current = self?.currentVersion ?? "1.0.0"
                            if cleanedLatest.compare(current, options: .numeric) == .orderedDescending {
                                for asset in assets {
                                    if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                                       let urlStr = asset["browser_download_url"] as? String {
                                        self?.downloadUrl = urlStr
                                        self?.updateAvailable = true
                                        break
                                    }
                                }
                                if self?.downloadUrl == nil {
                                    self?.errorMessage = "Update found, but no release package is available."
                                }
                            } else {
                                self?.updateAvailable = false
                            }
                        }
                    }
                } catch {
                    self?.errorMessage = "Failed to parse update data."
                }
            }
        }.resume()
    }
    
    public func installUpdate() {
        guard let urlStr = downloadUrl, let url = URL(string: urlStr) else { return }
        isDownloading = true
        downloadProgress = 0.0
        errorMessage = nil
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        let downloadTask = session.downloadTask(with: url)
        downloadTask.resume()
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async {
                self.downloadProgress = progress
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destinationUrl = URL(fileURLWithPath: "/tmp/AirspaceUpdate.zip")
        try? FileManager.default.removeItem(at: destinationUrl)
        
        do {
            try FileManager.default.moveItem(at: location, to: destinationUrl)
            DispatchQueue.main.async {
                self.isDownloading = false
                self.runInstallScript()
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = "Failed to prepare update package."
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func runInstallScript() {
        let appPath = Bundle.main.bundlePath
        let scriptContent = """
        #!/bin/bash
        sleep 1
        mkdir -p /tmp/AirspaceUpdateUnzipped
        unzip -q -o /tmp/AirspaceUpdate.zip -d /tmp/AirspaceUpdateUnzipped
        
        # Replace app
        rm -rf "\(appPath)"
        cp -R /tmp/AirspaceUpdateUnzipped/Airspace.app "\(appPath)"
        
        # Clean up
        rm -rf /tmp/AirspaceUpdateUnzipped
        rm -f /tmp/AirspaceUpdate.zip
        
        # Launch new version
        open "\(appPath)"
        
        # Self delete
        rm -- "$0"
        """
        
        let scriptPath = "/tmp/install_update.sh"
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            
            // Make script executable
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", scriptPath]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            // Run script detached
            let installProcess = Process()
            installProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            installProcess.arguments = [scriptPath]
            try installProcess.run()
            
            // Quit app
            NSApplication.shared.terminate(nil)
        } catch {
            self.errorMessage = "Failed to run update installer: \(error.localizedDescription)"
        }
    }
}
