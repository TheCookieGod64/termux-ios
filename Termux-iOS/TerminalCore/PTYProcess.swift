//
//  PTYProcess.swift
//  Termux-iOS
//
//  Pseudo-Terminal (PTY) Spawner for /var/jb Chroot & Rootless environments.
//  Target: iPhone 8 (iOS 15/16) | TrollStore | palera1n
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

public class PTYProcess {
    public var masterFD: Int32 = -1
    public var slaveFD: Int32 = -1
    public var childPID: pid_t = -1
    public var isRunning: Bool = false
    
    private var readSource: DispatchSourceRead?
    public var onDataReceived: ((Data) -> Void)?
    public var onProcessTerminated: ((Int32) -> Void)?
    
    public init() {}
    
    public func start(columns: Int = 80, rows: Int = 24) -> Bool {
        var master: Int32 = -1
        var slave: Int32 = -1
        
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        
        guard openpty(&master, &slave, nil, nil, &winSize) == 0 else {
            print("[PTYProcess] openpty failed: \(errno)")
            return false
        }
        
        self.masterFD = master
        self.slaveFD = slave
        
        // Prepare execution target: prefer jb-chroot helper if available
        let jbChrootPaths = [
            "/var/jb/usr/bin/jb-chroot",
            "/usr/local/bin/jb-chroot",
            "/usr/bin/jb-chroot"
        ]
        
        var execPath = DefaultConfig.defaultRootlessShell
        var useJbChroot = false
        
        for path in jbChrootPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                execPath = path
                useJbChroot = true
                break
            }
        }
        
        if !useJbChroot && !FileManager.default.isExecutableFile(atPath: execPath) {
            execPath = "/bin/bash"
            if !FileManager.default.isExecutableFile(atPath: execPath) {
                execPath = "/bin/sh"
            }
        }
        
        let pid = fork()
        if pid < 0 {
            print("[PTYProcess] fork failed: \(errno)")
            close(master)
            close(slave)
            return false
        }
        
        if pid == 0 {
            // Child process
            close(master)
            
            login_tty(slave)
            
            // Set environment for Termux-iOS
            setenv("TERM", "xterm-256color", 1)
            setenv("COLORTERM", "truecolor", 1)
            setenv("LANG", "en_US.UTF-8", 1)
            setenv("TERMUX_VERSION", "0.118.0-ios-pacman", 1)
            setenv("TERMUX_PKG_MANAGER", "pacman", 1)
            setenv("HOME", "/var/jb/var/mobile", 1)
            setenv("PREFIX", "/var/jb/usr", 1)
            setenv("PATH", "/var/jb/usr/local/sbin:/var/jb/usr/local/bin:/var/jb/usr/sbin:/var/jb/usr/bin:/var/jb/sbin:/var/jb/bin:/usr/local/bin:/usr/bin:/bin", 1)
            
            var args: [UnsafeMutablePointer<CChar>?] = []
            args.append(strdup((execPath as NSString).lastPathComponent))
            args.append(nil)
            
            execv(execPath, &args)
            
            // If execv fails, print error and exit
            perror("execv failed")
            exit(127)
        } else {
            // Parent process
            close(slave)
            self.slaveFD = -1
            self.childPID = pid
            self.isRunning = true
            
            startReading()
            return true
        }
    }
    
    private func startReading() {
        guard masterFD >= 0 else { return }
        
        let queue = DispatchQueue(label: "com.termux.ios.ptyread", qos: .userInteractive)
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        
        source.setEventHandler { [weak self] in
            guard let self = self, self.masterFD >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                DispatchQueue.main.async {
                    self.onDataReceived?(data)
                }
            } else if bytesRead <= 0 {
                self.terminate()
            }
        }
        
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.masterFD >= 0 {
                close(self.masterFD)
                self.masterFD = -1
            }
        }
        
        self.readSource = source
        source.resume()
    }
    
    public func writeData(_ data: Data) {
        guard masterFD >= 0 && isRunning else { return }
        data.withUnsafeBytes { bufferPointer in
            if let baseAddress = bufferPointer.baseAddress {
                _ = write(masterFD, baseAddress, data.count)
            }
        }
    }
    
    public func writeString(_ str: String) {
        if let data = str.data(using: .utf8) {
            writeData(data)
        }
    }
    
    public func setWindowSize(columns: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterFD, UInt28(TIOCSWINSZ), &winSize)
    }
    
    public func terminate() {
        guard isRunning else { return }
        isRunning = false
        
        readSource?.cancel()
        readSource = nil
        
        if childPID > 0 {
            kill(childPID, SIGTERM)
            var status: Int32 = 0
            waitpid(childPID, &status, WNOHANG)
            childPID = -1
            
            DispatchQueue.main.async {
                self.onProcessTerminated?(status)
            }
        }
    }
}
