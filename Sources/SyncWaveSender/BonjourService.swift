// BonjourService.swift
// Handles mDNS/Bonjour service advertising and discovery
//
// Sender advertises itself as a service on the LAN
// Receiver browses for available sender services

import Foundation
import Network

// MARK: - Bonjour Service

/// Advertises or discovers SyncWave services on the LAN via Bonjour (mDNS)
class BonjourService: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    // MARK: - Service Information

    struct Service {
        let name: String              // e.g., "Living Room Mac"
        let host: String              // e.g., "192.168.1.100"
        let port: Int
        let type: ServiceType
        let isReachable: Bool

        enum ServiceType {
            case sender
            case receiver
        }
    }

    // MARK: - Delegates

    var onServiceFound: ((Service) -> Void)?
    var onServiceLost: ((Service) -> Void)?
    var onError: ((Error) -> Void)?

    private var advertisingService: NetService?
    private var browserService: NetServiceBrowser?
    private var discoveredServices: [String: NetService] = [:]
    private let queue = DispatchQueue(label: "com.syncwave.bonjour")

    // MARK: - Advertising (Sender)

    func startAdvertisingAsService(
        name: String,
        port: UInt16,
        type: Service.ServiceType
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let serviceType = type == .sender ? "_syncwave-send._tcp" : "_syncwave-recv._tcp"

            self.advertisingService = NetService(
                domain: "local.",
                type: serviceType,
                name: name,
                port: Int32(port)
            )

            self.advertisingService?.delegate = self
            self.advertisingService?.publish()

            print("[Bonjour] Advertising service: \(name) (\(serviceType))")
        }
    }

    func stopAdvertising() {
        queue.async { [weak self] in
            self?.advertisingService?.stop()
            self?.advertisingService = nil
            print("[Bonjour] Stopped advertising")
        }
    }

    // MARK: - Discovery (Receiver)

    func startBrowsingForServices(type: Service.ServiceType) {
        queue.async { [weak self] in
            guard let self else { return }

            let serviceType = type == .sender ? "_syncwave-send._tcp" : "_syncwave-recv._tcp"

            self.browserService = NetServiceBrowser()
            self.browserService?.delegate = self
            self.browserService?.searchForServices(ofType: serviceType, inDomain: "local.")

            print("[Bonjour] Browsing for services: \(serviceType)")
        }
    }

    func stopBrowsing() {
        queue.async { [weak self] in
            self?.browserService?.stop()
            self?.browserService = nil
            print("[Bonjour] Stopped browsing")
        }
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind netService: NetService,
        moreComing: Bool
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            self.discoveredServices[netService.name] = netService
            netService.delegate = self
            netService.resolve(withTimeout: 5.0)
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove netService: NetService,
        moreComing: Bool
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            if let removed = self.discoveredServices.removeValue(forKey: netService.name) {
                let service = Service(
                    name: removed.name,
                    host: removed.hostName ?? "unknown",
                    port: Int(removed.port),
                    type: removed.type.contains("send") ? .sender : .receiver,
                    isReachable: false
                )
                DispatchQueue.main.async {
                    self.onServiceLost?(service)
                }
                print("[Bonjour] Service lost: \(removed.name)")
            }
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        let error = NSError(
            domain: "NetServiceBrowser",
            code: errorDict[NetServiceBrowser.errorCode]?.intValue ?? -1,
            userInfo: errorDict as? [String: Any]
        )
        DispatchQueue.main.async {
            self.onError?(error)
        }
        print("[Bonjour] Browse error: \(error.localizedDescription)")
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        queue.async { [weak self] in
            guard let self else { return }

            guard let addresses = sender.addresses, !addresses.isEmpty,
                  let ipAddress = self.ipFromSocketAddress(addresses[0]) else {
                print("[Bonjour] Failed to resolve \(sender.name)")
                return
            }

            let service = Service(
                name: sender.name,
                host: ipAddress,
                port: Int(sender.port),
                type: sender.type.contains("send") ? .sender : .receiver,
                isReachable: true
            )

            DispatchQueue.main.async {
                self.onServiceFound?(service)
            }

            print("[Bonjour] Service resolved: \(sender.name) at \(ipAddress):\(sender.port)")
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let error = NSError(
            domain: "NetService",
            code: errorDict[NetService.errorCode]?.intValue ?? -1,
            userInfo: errorDict as? [String: Any]
        )
        DispatchQueue.main.async {
            self.onError?(error)
        }
        print("[Bonjour] Resolve error for \(sender.name): \(error.localizedDescription)")
    }

    // MARK: - Helper

    private func ipFromSocketAddress(_ data: Data) -> String? {
        let bytes = (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count)

        // Check for IPv4 (sockaddr_in)
        if data.count >= MemoryLayout<sockaddr_in>.size {
            let addr = UnsafeRawPointer(bytes).assumingMemoryBound(to: sockaddr_in.self).pointee
            if addr.sin_family == UInt8(AF_INET) {
                let ipBytes = withUnsafeBytes(of: addr.sin_addr.s_addr) { Array($0) }
                return ipBytes.map(String.init).joined(separator: ".")
            }
        }

        // Check for IPv6 (sockaddr_in6)
        if data.count >= MemoryLayout<sockaddr_in6>.size {
            let addr = UnsafeRawPointer(bytes).assumingMemoryBound(to: sockaddr_in6.self).pointee
            if addr.sin6_family == UInt8(AF_INET6) {
                let ipBytes = withUnsafeBytes(of: addr.sin6_addr.__uint8_t) { Array($0) }
                let ipString = stride(from: 0, to: 16, by: 2).map { i -> String in
                    let byte1 = String(format: "%x", ipBytes[i])
                    let byte2 = String(format: "%x", ipBytes[i + 1])
                    return byte1 + byte2
                }.joined(separator: ":")
                return ipString
            }
        }

        return nil
    }
}
