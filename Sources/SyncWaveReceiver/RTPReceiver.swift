// RTPReceiver.swift
// Listens for RTP packets on a UDP multicast group.
//
// STATUS: Skeleton with implementation notes. Phase 4 of ROADMAP.md.

import Foundation

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

    let multicastGroup: String
    let port: UInt16

    /// Called on a background thread for each received packet.
    var onPacket: ((IncomingRTPPacket) -> Void)?

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

    init(multicastGroup: String = "239.0.0.1", port: UInt16 = 5004) {
        self.multicastGroup = multicastGroup
        self.port = port
    }

    func start() {
        // TODO: implement per notes above
        print("[RTPReceiver] start() — not yet implemented.")
    }

    func stop() {
        // TODO: close socket, stop receive loop
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
}
