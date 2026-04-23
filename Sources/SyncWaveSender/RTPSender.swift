// RTPSender.swift
// Sends Opus-encoded audio as RTP packets over UDP multicast.
//
// STATUS: Skeleton with implementation notes. Phase 3 of ROADMAP.md.

import Foundation
import Darwin

// MARK: - RTP Packet

/// Minimal RTP packet (RFC 3550).
/// Full spec: https://www.rfc-editor.org/rfc/rfc3550
struct RTPPacket {
    // Header fields
    let version: UInt8 = 2          // Always 2
    let payloadType: UInt8 = 111    // 111 = dynamic (Opus)
    var sequenceNumber: UInt16
    var timestamp: UInt32           // Sample offset from stream start (at 48kHz)
    let ssrc: UInt32                // Random ID for this stream

    // Payload
    var payload: Data               // Opus encoded frame

    /// Serialize to bytes for UDP transmission.
    func toData() -> Data {
        var data = Data(capacity: 12 + payload.count)

        // Byte 0: V=2, P=0, X=0, CC=0
        data.append(0b10000000)
        // Byte 1: M=0, PT=111
        data.append(payloadType & 0x7F)
        // Bytes 2-3: sequence number (big endian)
        data.append(contentsOf: sequenceNumber.bigEndianBytes)
        // Bytes 4-7: timestamp (big endian)
        data.append(contentsOf: timestamp.bigEndianBytes)
        // Bytes 8-11: SSRC (big endian)
        data.append(contentsOf: ssrc.bigEndianBytes)
        // Bytes 12+: Opus payload
        data.append(payload)

        return data
    }
}

// MARK: - RTPSender

/// Sends RTP packets to a UDP multicast group.
///
/// All receivers on the LAN that have joined the multicast group
/// will receive every packet exactly once, regardless of how many
/// receivers there are (the network handles fan-out).
class RTPSender {

    let multicastGroup: String  // e.g. "239.0.0.1"
    let port: UInt16            // e.g. 5004

    private var sequenceNumber: UInt16 = 0
    private var timestamp: UInt32 = 0
    private let ssrc: UInt32 = UInt32.random(in: 0...UInt32.max)
    private let samplesPerFrame: UInt32
    private var socketFD: Int32 = -1

    // MARK: - Implementation notes
    //
    // Sending UDP multicast in Swift using POSIX sockets:
    //
    //   let sock = socket(AF_INET, SOCK_DGRAM, 0)
    //
    //   // Set TTL (time-to-live) — 1 = stays on local subnet
    //   var ttl: UInt8 = 1
    //   setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))
    //
    //   // Set up destination address
    //   var addr = sockaddr_in()
    //   addr.sin_family = sa_family_t(AF_INET)
    //   addr.sin_port = port.bigEndian
    //   addr.sin_addr.s_addr = inet_addr(multicastGroup)
    //
    //   // Send packet
    //   let packetData = packet.toData()
    //   packetData.withUnsafeBytes { ptr in
    //       sendto(sock, ptr.baseAddress, packetData.count, 0,
    //              UnsafePointer(&addr) as! UnsafePointer<sockaddr>,
    //              socklen_t(MemoryLayout<sockaddr_in>.size))
    //   }
    //
    // Alternatively use NWConnection with NWEndpoint.hostPort — higher level but
    // multicast support is less direct. POSIX sockets are more straightforward here.

    init(multicastGroup: String = "239.0.0.1", port: UInt16 = 5004, samplesPerFrame: Int = 480) {
        self.multicastGroup = multicastGroup
        self.port = port
        self.samplesPerFrame = UInt32(samplesPerFrame)
        do {
            try setupSocket()
            print("[RTPSender] ready. target=\(multicastGroup):\(port) ssrc=\(ssrc)")
        } catch {
            print("[RTPSender] socket setup failed: \(error)")
        }
    }

    /// Send one Opus frame as an RTP packet.
    func send(_ opusFrame: Data) {
        guard socketFD >= 0 else {
            print("[RTPSender] send skipped: socket not available.")
            return
        }

        let packet = RTPPacket(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            ssrc: ssrc,
            payload: opusFrame
        )

        let packetData = packet.toData()
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian

        let addressSetResult = multicastGroup.withCString { ip in
            inet_pton(AF_INET, ip, &destination.sin_addr)
        }
        guard addressSetResult == 1 else {
            print("[RTPSender] invalid multicast address: \(multicastGroup)")
            return
        }

        let bytesSent = packetData.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress else { return -1 }
            return withUnsafePointer(to: &destination) { ptr -> ssize_t in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(socketFD, baseAddress, packetData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if bytesSent < 0 {
            print("[RTPSender] sendto failed: \(String(cString: strerror(errno)))")
        }

        sequenceNumber &+= 1              // wraps at 65535
        timestamp &+= samplesPerFrame     // advance by one frame's worth of samples
    }

    deinit {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func setupSocket() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw RTPSenderError.socketCreateFailed(String(cString: strerror(errno)))
        }

        var ttl: UInt8 = 1
        let ttlResult = withUnsafePointer(to: &ttl) { ptr in
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, ptr, socklen_t(MemoryLayout<UInt8>.size))
        }
        guard ttlResult == 0 else {
            close(fd)
            throw RTPSenderError.socketOptionFailed("IP_MULTICAST_TTL", String(cString: strerror(errno)))
        }

        socketFD = fd
    }
}

// MARK: - Helpers

private extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8(self >> 8), UInt8(self & 0xFF)]
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8(self >> 24), UInt8((self >> 16) & 0xFF),
         UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

private enum RTPSenderError: LocalizedError {
    case socketCreateFailed(String)
    case socketOptionFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .socketCreateFailed(reason):
            return "Failed to create UDP socket: \(reason)"
        case let .socketOptionFailed(option, reason):
            return "Failed setting socket option \(option): \(reason)"
        }
    }
}
