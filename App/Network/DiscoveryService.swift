import Foundation

struct DiscoveredSender: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
}

final class DiscoveryService: NSObject {
    private let serviceType = "_syncwave._udp."
    private var browser: NetServiceBrowser?
    private var foundServices: [NetService] = []
    private var ownService: NetService?
    private var onUpdate: (([DiscoveredSender]) -> Void)?

    func startBrowsing(onUpdate: @escaping ([DiscoveredSender]) -> Void) {
        stopBrowsing()
        self.onUpdate = onUpdate
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: serviceType, inDomain: "local.")
    }

    func stopBrowsing() {
        browser?.stop()
        browser = nil
        foundServices.removeAll()
        onUpdate?([])
    }

    func startAdvertising(name: String, host: String, port: UInt16) {
        stopAdvertising()
        let service = NetService(domain: "local.", type: serviceType, name: name, port: Int32(port))
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "host": host.data(using: .utf8) ?? Data(),
            "port": "\(port)".data(using: .utf8) ?? Data()
        ]))
        ownService = service
        service.publish()
    }

    func stopAdvertising() {
        ownService?.stop()
        ownService = nil
    }
}

extension DiscoveryService: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        foundServices.append(service)
        service.resolve(withTimeout: 2.0)
        if !moreComing {
            publishFoundServices()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        foundServices.removeAll { $0 == service }
        if !moreComing {
            publishFoundServices()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        publishFoundServices()
    }

    private func publishFoundServices() {
        let senders: [DiscoveredSender] = foundServices.compactMap { service in
            guard let txt = service.txtRecordData(),
                  !txt.isEmpty else {
                return nil
            }
            let dict = NetService.dictionary(fromTXTRecord: txt)
            guard
                  let hostData = dict["host"],
                  let host = String(data: hostData, encoding: .utf8),
                  let portData = dict["port"],
                  let portString = String(data: portData, encoding: .utf8),
                  let port = UInt16(portString) else {
                return nil
            }
            return DiscoveredSender(id: "\(host):\(port)", name: service.name, host: host, port: port)
        }
        onUpdate?(senders)
    }
}
