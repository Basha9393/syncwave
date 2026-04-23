// RTPReceiver.swift
// Listens for RTP packets on a UDP multicast group.
//
// STATUS: Skeleton with implementation notes. Phase 4 of ROADMAP.md.

import Foundation
import Darwin

// MARK: - Parsed RTP Packet

struct IncomingRTPPacket {
    let sequenceNumber: UInt16
    let timestamp: UInt32       // RTP sample timestamp
    let ssrc: UInt32
    let payload: Data           // Opus frame bytes
    let receivedAt: UInt64      // mach_absolute_time() when packet arrived
}

// MARK: - RTPReceiver

/// Joins a UDP multicast group and delivers parsed RTP packets to a callback.
class RTPReceiver {
    enum TransportMode {
        case multicast
        case unicast
    }

    let listenAddress: String
    let port: UInt16
    let transportMode: TransportMode

    /// Called on a background thread for each received packet.
    var onPacket: ((IncomingRTPPacket) -> Void)?
    var onError: ((String) -> Void)?

    private var socketFD: Int32 = -1
    private var isRunning = false
    private let receiveQueue = DispatchQueue(label: "com.syncwave.rtp-receiver", qos: .userInitiated)

    // MARK: - Implementation notes
    //
    // Joining a multicast group with POSIX sockets:
    //
    //   let sock = socket(AF_INET, SOCK_DGRAM, 0)
    //
    //   // Allow multiple sockets on same port (for running sender + receiver on same Mac)
    //   var reuse: Int32 = 1
    //   setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
    //   setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
    //
    //   // Bind to the multicast port
    //   var bindAddr = sockaddr_in()
    //   bindAddr.sin_family = sa_family_t(AF_INET)
    //   bindAddr.sin_port = port.bigEndian
    //   bindAddr.sin_addr.s_addr = INADDR_ANY
    //   bind(sock, ...)
    //
    //   // Join the multicast group
    //   var mreq = ip_mreq()
    //   mreq.imr_multiaddr.s_addr = inet_addr(multicastGroup)
    //   mreq.imr_interface.s_addr = INADDR_ANY
    //   setsockopt(sock, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout.size(ofValue: mreq)))
    //
    // Receive loop (run on a background thread):
    //   var buffer = [UInt8](repeating: 0, count: 65535)
    //   while running {
    //       let n = recv(sock, &buffer, buffer.count, 0)
    //       if n > 12 {  // minimum RTP header is 12 bytes
    //           let packet = parseRTP(Data(buffer[0..<n]))
    //           onPacket?(packet)
    //       }
    //   }

    init(listenAddress: String = "239.0.0.1", port: UInt16 = 5004, transportMode: TransportMode = .multicast) {
        self.listenAddress = listenAddress
        self.port = port
        self.transportMode = transportMode
    }

    func start() {
        guard !isRunning else { return }
        do {
            try setupSocket()
            isRunning = true
            receiveQueue.async { [weak self] in
                self?.receiveLoop()
            }
            print("[RTPReceiver] listening mode=\(transportMode) on \(listenAddress):\(port)")
        } catch {
            onError?("[RTPReceiver] failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        isRunning = false
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        print("[RTPReceiver] stopped.")
    }

    // MARK: - RTP parsing

    private func parseRTP(_ data: Data) -> IncomingRTPPacket? {
        guard data.count >= 12 else { return nil }

        let seq = UInt16(data[2]) << 8 | UInt16(data[3])
        let ts  = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        let ssrc = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
        let payload = data.subdata(in: 12..<data.count)

        return IncomingRTPPacket(
            sequenceNumber: seq,
            timestamp: ts,
            ssrc: ssrc,
            payload: payload,
            receivedAt: mach_absolute_time()
        )
    }

    private func setupSocket() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw RTPReceiverError.socketCreateFailed(String(cString: strerror(errno)))
        }

        var reuse: Int32 = 1
        let reuseAddrResult = withUnsafePointer(to: &reuse) { ptr in
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, ptr, socklen_t(MemoryLayout<Int32>.size))
        }
        guard reuseAddrResult == 0 else {
            close(fd)
            throw RTPReceiverError.socketOptionFailed("SO_REUSEADDR", String(cString: strerror(errno)))
        }

        #if os(macOS)
        let reusePortResult = withUnsafePointer(to: &reuse) { ptr in
            setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, ptr, socklen_t(MemoryLayout<Int32>.size))
        }
        guard reusePortResult == 0 else {
            close(fd)
            throw RTPReceiverError.socketOptionFailed("SO_REUSEPORT", String(cString: strerror(errno)))
        }
        #endif

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = port.bigEndian
        bindAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &bindAddress) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw RTPReceiverError.bindFailed(String(cString: strerror(errno)))
        }

        if transportMode == .multicast {
            var membership = ip_mreq()
            let groupAddressResult = listenAddress.withCString { ip in
                inet_pton(AF_INET, ip, &membership.imr_multiaddr)
            }
            guard groupAddressResult == 1 else {
                close(fd)
                throw RTPReceiverError.invalidAddress(listenAddress)
            }
            membership.imr_interface = in_addr(s_addr: INADDR_ANY)

            let addMembershipResult = withUnsafePointer(to: &membership) { ptr in
                setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, ptr, socklen_t(MemoryLayout<ip_mreq>.size))
            }
            guard addMembershipResult == 0 else {
                close(fd)
                throw RTPReceiverError.socketOptionFailed("IP_ADD_MEMBERSHIP", String(cString: strerror(errno)))
            }
        }

        socketFD = fd
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 65_535)

        while isRunning {
            let receivedCount = recv(socketFD, &buffer, buffer.count, 0)
            if receivedCount <= 0 {
                if isRunning {
                    onError?("[RTPReceiver] recv failed: \(String(cString: strerror(errno)))")
                }
                break
            }

            guard receivedCount > 12 else { continue }
            let packetData = Data(buffer[0..<Int(receivedCount)])
            guard let packet = parseRTP(packetData) else { continue }
            onPacket?(packet)
        }
    }
}

private enum RTPReceiverError: LocalizedError {
    case socketCreateFailed(String)
    case socketOptionFailed(String, String)
    case bindFailed(String)
    case invalidAddress(String)

    var errorDescription: String? {
        switch self {
        case let .socketCreateFailed(reason):
            return "Failed to create UDP socket: \(reason)"
        case let .socketOptionFailed(option, reason):
            return "Failed setting socket option \(option): \(reason)"
        case let .bindFailed(reason):
            return "Failed to bind receiver socket: \(reason)"
        case let .invalidAddress(address):
            return "Invalid multicast address: \(address)"
        }
    }
}
