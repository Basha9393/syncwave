# Networking

Details on the RTP/UDP multicast transport layer.

---

## Why UDP over TCP

TCP retransmits dropped packets. For streaming audio, a retransmit arrives too late to be played — the moment has passed. The result is a stutter, not the intended audio. UDP drops the packet and moves on. Combined with Opus packet loss concealment (PLC), a dropped packet produces a very brief, usually inaudible artifact rather than a stutter.

AirPlay uses TCP-based buffering, which is why it needs a 2-second buffer — it's guaranteeing delivery, at the cost of latency.

## Why Multicast

With **unicast**, the sender transmits one copy of each packet per receiver:
- 1 receiver → 1× bandwidth
- 3 receivers → 3× bandwidth
- 10 receivers → 10× bandwidth

With **multicast**, the sender transmits one copy and the router fans it out:
- 1 receiver → 1× bandwidth
- 3 receivers → still 1× bandwidth on the sender's link
- Receivers join a multicast group by IP address

More importantly for sync: all receivers get the **same packet at the same moment**. There's no "first receiver gets it slightly earlier" problem.

## Addresses and Ports

| Setting | Value | Notes |
|---|---|---|
| Multicast group | `239.0.0.1` | Private multicast, stays on LAN |
| Port | `5004` | Standard RTP audio port |
| TTL | `1` | Prevents packets from leaving the local subnet |
| Protocol | UDP | No connection setup, no retransmit |

## RTP Payload Type

RTP uses a "payload type" field to indicate the codec. Opus uses dynamic payload types (96–127). SyncWave uses **PT=111** by convention (same as WebRTC). The sender and receiver just need to agree.

## Packet Size

At 10ms Opus frames, 128kbps stereo:
- Opus frame size ≈ 160 bytes
- RTP header: 12 bytes
- Total per packet: ~172 bytes
- Packet rate: 100 packets/second
- Bandwidth: ~140 kbps

This is extremely low. Even a congested home Wi-Fi network has no trouble with this.

## Firewall / Network Notes

- UDP multicast must not be blocked by any firewall on the Macs
- If using a managed switch/router, ensure IGMP snooping is enabled (usually default)
- Enterprise Wi-Fi networks often block multicast — for those, fall back to unicast

## Verifying with Wireshark

To check packets are arriving on a receiver:
1. Install Wireshark (https://www.wireshark.org)
2. Start capture on your Wi-Fi interface
3. Filter: `udp.port == 5004`
4. Run the sender — packets should appear

## Sequence Numbers and Reordering

RTP packets include a 16-bit sequence number. The jitter buffer on the receiver uses this to:
- Detect missing packets (gap in sequence)
- Reorder packets that arrive out of sequence (uncommon on LAN, but possible)
- Trigger PLC for packets that never arrive
