//! WebRTC data channels (RFC 8831) over a call's DTLS session: SCTP
//! (sctp-proto, sans-IO) inside DTLS application data, and DCEP (RFC 8832)
//! to open a named channel. Teams' meeting media processors carry their
//! media control plane on one ("main-channel"; see docs/spec/meeting-video.md).

use bytes::Bytes;
use sctp_proto::{
    Association, AssociationHandle, ClientConfig, DatagramEvent, Endpoint, EndpointConfig, Event,
    PayloadProtocolIdentifier, ServerConfig, StreamEvent,
};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// DCEP message types (RFC 8832 §5).
const DCEP_OPEN: u8 = 0x03;
const DCEP_ACK: u8 = 0x02;
/// DATA_CHANNEL_RELIABLE: reliable and ordered.
const CHANNEL_RELIABLE: u8 = 0x00;
/// The most SCTP user data we hand DTLS in one record; leaves room for
/// DTLS, UDP/IP and TURN headers under a 1280-byte path MTU.
const SCTP_MTU: u32 = 1200;

/// What carries the SCTP packets: one DTLS application-data record each.
pub trait Datagrams {
    /// The next record's payload, waiting a little; `Ok(None)` when none
    /// came; an error once the session is gone.
    fn recv(&mut self) -> std::io::Result<Option<Vec<u8>>>;
    fn send(&mut self, packet: &[u8]) -> std::io::Result<()>;
}

impl<S: std::io::Read + std::io::Write> Datagrams for openssl::ssl::SslStream<S> {
    fn recv(&mut self) -> std::io::Result<Option<Vec<u8>>> {
        let mut buf = vec![0u8; 65536];
        match self.ssl_read(&mut buf) {
            Ok(n) => {
                buf.truncate(n);
                Ok(Some(buf))
            }
            Err(e) if e.code() == openssl::ssl::ErrorCode::WANT_READ => Ok(None),
            Err(e) if e.code() == openssl::ssl::ErrorCode::ZERO_RETURN => Err(std::io::Error::new(
                std::io::ErrorKind::ConnectionAborted,
                "DTLS session closed",
            )),
            Err(e) => match e.io_error() {
                Some(io) if io.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
                _ => Err(std::io::Error::other(e.to_string())),
            },
        }
    }

    fn send(&mut self, packet: &[u8]) -> std::io::Result<()> {
        self.ssl_write(packet)
            .map(|_| ())
            .map_err(|e| std::io::Error::other(e.to_string()))
    }
}

/// Something from the channel.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DataEvent {
    /// The channel is open: messages can go.
    Open,
    /// A whole message (binary or text).
    Message(Vec<u8>),
    /// The association or the DTLS session ended.
    Closed,
}

/// Sends messages on an open channel (binary, PPID 53).
#[derive(Clone)]
pub struct DataSender(std::sync::mpsc::Sender<Vec<u8>>);

impl DataSender {
    #[cfg(test)]
    pub(crate) fn for_test(tx: std::sync::mpsc::Sender<Vec<u8>>) -> Self {
        Self(tx)
    }

    /// Queue a message; false once the channel's thread has ended.
    pub fn send(&self, message: Vec<u8>) -> bool {
        self.0.send(message).is_ok()
    }
}

/// Open the data channel `label` on stream `stream_id` (even when we are
/// the DTLS client, RFC 8832 §6) as the SCTP client, on a thread of its
/// own. Messages queued before the channel opens go once it does.
pub fn open<T: Datagrams + Send + 'static>(
    transport: T,
    label: &str,
    stream_id: u16,
) -> (DataSender, tokio::sync::mpsc::UnboundedReceiver<DataEvent>) {
    let (out_tx, out_rx) = std::sync::mpsc::channel::<Vec<u8>>();
    let (ev_tx, ev_rx) = tokio::sync::mpsc::unbounded_channel();
    let label = label.to_string();
    let spawned = std::thread::Builder::new()
        .name("ost-sctp".into())
        .spawn(move || {
            if let Err(e) = run(transport, &label, stream_id, &out_rx, &ev_tx) {
                tracing::info!("Data channel {label:?} ended: {e:#}");
            }
            let _ = ev_tx.send(DataEvent::Closed);
        });
    if let Err(e) = spawned {
        tracing::warn!("Data channel thread failed to start: {e}");
    }
    (DataSender(out_tx), ev_rx)
}

/// The DCEP DATA_CHANNEL_OPEN for a reliable, ordered channel.
pub fn dcep_open(label: &str) -> Vec<u8> {
    let label = label.as_bytes();
    let mut m = vec![DCEP_OPEN, CHANNEL_RELIABLE];
    m.extend_from_slice(&0u16.to_be_bytes()); // priority
    m.extend_from_slice(&0u32.to_be_bytes()); // reliability parameter
    m.extend_from_slice(&(label.len() as u16).to_be_bytes());
    m.extend_from_slice(&0u16.to_be_bytes()); // protocol length
    m.extend_from_slice(label);
    m
}

fn run<T: Datagrams>(
    mut transport: T,
    label: &str,
    stream_id: u16,
    out_rx: &std::sync::mpsc::Receiver<Vec<u8>>,
    events: &tokio::sync::mpsc::UnboundedSender<DataEvent>,
) -> anyhow::Result<()> {
    // sctp-proto routes by address; DTLS already ties us to one peer.
    let remote = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 5000);
    let mut endpoint_config = EndpointConfig::new();
    endpoint_config.max_payload_size(SCTP_MTU);
    // Both ends may open the association (WebRTC peers each send INIT);
    // whichever comes up first carries the channel.
    let mut endpoint = Endpoint::new(
        Arc::new(endpoint_config),
        Some(Arc::new(ServerConfig::new())),
    );
    let mut assocs: HashMap<AssociationHandle, Association> = HashMap::new();
    let (ours, assoc) = endpoint
        .connect(ClientConfig::default(), remote)
        .map_err(|e| anyhow::anyhow!("SCTP connect: {e:?}"))?;
    assocs.insert(ours, assoc);
    let mut active: Option<AssociationHandle> = None;
    let mut pending: Vec<Vec<u8>> = Vec::new();

    loop {
        // In: one DTLS record (waits briefly when there's none).
        if let Some(packet) = transport.recv()? {
            match endpoint.handle(Instant::now(), remote, None, None, Bytes::from(packet)) {
                Some((h, DatagramEvent::NewAssociation(a))) => {
                    tracing::debug!("Data channel {label:?}: the peer opened an association");
                    assocs.insert(h, a);
                }
                Some((h, DatagramEvent::AssociationEvent(ev))) => {
                    if let Some(a) = assocs.get_mut(&h) {
                        a.handle_event(ev);
                    }
                }
                None => {}
            }
        }
        let now = Instant::now();
        for a in assocs.values_mut() {
            if a.poll_timeout().is_some_and(|t| t <= now) {
                a.handle_timeout(now);
            }
        }

        // Out: what the caller queued.
        loop {
            match out_rx.try_recv() {
                Ok(m) => pending.push(m),
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                // The caller is gone: close.
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    for (h, a) in assocs.iter_mut() {
                        let _ = a.close();
                        flush(a, &mut transport, *h, &mut endpoint)?;
                    }
                    return Ok(());
                }
            }
        }
        if let Some(a) = active.and_then(|h| assocs.get_mut(&h))
            && !pending.is_empty()
        {
            let mut stream = a.stream(stream_id)?;
            for m in pending.drain(..) {
                let ppi = if m.is_empty() {
                    PayloadProtocolIdentifier::BinaryEmpty
                } else {
                    PayloadProtocolIdentifier::Binary
                };
                let body = if m.is_empty() { vec![0] } else { m };
                stream.write_sctp(&Bytes::from(body), ppi)?;
            }
        }

        let handles: Vec<AssociationHandle> = assocs.keys().copied().collect();
        for h in handles {
            let Some(a) = assocs.get_mut(&h) else {
                continue;
            };
            while let Some(event) = a.poll() {
                match event {
                    Event::Connected if active.is_none() => {
                        let mut stream =
                            a.open_stream(stream_id, PayloadProtocolIdentifier::Dcep)?;
                        stream.write_sctp(
                            &Bytes::from(dcep_open(label)),
                            PayloadProtocolIdentifier::Dcep,
                        )?;
                        // Ordered: data may follow the OPEN at once (RFC 8832 §6).
                        active = Some(h);
                        tracing::info!("Data channel {label:?} opened");
                        let _ = events.send(DataEvent::Open);
                    }
                    Event::HandshakeFailed { reason } | Event::AssociationLost { reason }
                        if active == Some(h) =>
                    {
                        anyhow::bail!("SCTP association: {reason:?}");
                    }
                    Event::Stream(StreamEvent::Readable { id }) if active == Some(h) => {
                        let mut stream = a.stream(id)?;
                        while let Some(chunks) = stream.read_sctp()? {
                            let mut buf = vec![0u8; chunks.len()];
                            let n = chunks.read(&mut buf)?;
                            buf.truncate(n);
                            match chunks.ppi {
                                PayloadProtocolIdentifier::Dcep => {
                                    if buf.first() == Some(&DCEP_ACK) {
                                        tracing::debug!("Data channel {label:?} acknowledged");
                                    }
                                }
                                PayloadProtocolIdentifier::BinaryEmpty
                                | PayloadProtocolIdentifier::StringEmpty => {
                                    let _ = events.send(DataEvent::Message(Vec::new()));
                                }
                                _ => {
                                    let _ = events.send(DataEvent::Message(buf));
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
            // Streams the peer opens are taken (and read above).
            while a.accept_stream().is_some() {}
            flush(a, &mut transport, h, &mut endpoint)?;
        }
        if active.is_some_and(|h| assocs.get(&h).is_none_or(Association::is_closed)) {
            anyhow::bail!("SCTP association closed");
        }
        // An association that ended before coming up is dropped.
        assocs.retain(|h, a| Some(*h) == active || !a.is_closed());
        if assocs.is_empty() {
            anyhow::bail!("SCTP association failed");
        }
    }
}

/// Send what the association has queued, and pass its endpoint events on.
fn flush<T: Datagrams>(
    assoc: &mut Association,
    transport: &mut T,
    handle: AssociationHandle,
    endpoint: &mut Endpoint,
) -> anyhow::Result<()> {
    while let Some(ev) = assoc.poll_endpoint_event() {
        if let Some(back) = endpoint.handle_event(handle, ev) {
            assoc.handle_event(back);
        }
    }
    while let Some(t) = assoc.poll_transmit(Instant::now()) {
        if let sctp_proto::Payload::RawEncode(parts) = t.payload {
            for p in parts {
                transport.send(&p)?;
            }
        }
    }
    Ok(())
}

/// How long `Datagrams::recv` on a DTLS session should wait for a record:
/// short, so queued messages and SCTP timers aren't held up.
pub const RECV_WAIT: Duration = Duration::from_millis(20);

#[cfg(test)]
mod tests {
    use super::*;

    /// One end of an in-memory datagram pipe.
    struct Pipe {
        rx: std::sync::mpsc::Receiver<Vec<u8>>,
        tx: std::sync::mpsc::Sender<Vec<u8>>,
    }

    impl Datagrams for Pipe {
        fn recv(&mut self) -> std::io::Result<Option<Vec<u8>>> {
            match self.rx.recv_timeout(Duration::from_millis(5)) {
                Ok(p) => Ok(Some(p)),
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => Ok(None),
                Err(_) => Err(std::io::ErrorKind::BrokenPipe.into()),
            }
        }
        fn send(&mut self, packet: &[u8]) -> std::io::Result<()> {
            let _ = self.tx.send(packet.to_vec());
            Ok(())
        }
    }

    #[test]
    fn dcep_open_is_rfc_8832() {
        assert_eq!(
            dcep_open("main-channel"),
            [
                &[0x03, 0x00, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0][..],
                b"main-channel"
            ]
            .concat()
        );
    }

    /// Our channel against an sctp-proto server that acknowledges the
    /// OPEN and echoes messages back, as a media processor answers them.
    #[tokio::test]
    async fn opens_a_channel_and_exchanges_messages() {
        let (a_tx, b_rx) = std::sync::mpsc::channel();
        let (b_tx, a_rx) = std::sync::mpsc::channel();
        let ours = Pipe { rx: a_rx, tx: a_tx };
        let mut theirs = Pipe { rx: b_rx, tx: b_tx };

        std::thread::spawn(move || {
            let remote = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 5000);
            let mut ep = Endpoint::new(
                Arc::new(EndpointConfig::new()),
                Some(Arc::new(ServerConfig::new())),
            );
            let mut assoc: Option<(AssociationHandle, sctp_proto::Association)> = None;
            let deadline = Instant::now() + Duration::from_secs(10);
            while Instant::now() < deadline {
                if let Ok(Some(p)) = theirs.recv() {
                    match ep.handle(Instant::now(), remote, None, None, Bytes::from(p)) {
                        Some((h, DatagramEvent::NewAssociation(a))) => assoc = Some((h, a)),
                        Some((_, DatagramEvent::AssociationEvent(ev))) => {
                            if let Some((_, a)) = assoc.as_mut() {
                                a.handle_event(ev)
                            }
                        }
                        None => {}
                    }
                }
                let Some((h, a)) = assoc.as_mut() else {
                    continue;
                };
                let now = Instant::now();
                if a.poll_timeout().is_some_and(|t| t <= now) {
                    a.handle_timeout(now);
                }
                while let Some(ev) = a.poll() {
                    if let Event::Stream(StreamEvent::Readable { id }) = ev {
                        let mut s = a.stream(id).unwrap();
                        while let Some(c) = s.read_sctp().unwrap() {
                            let mut buf = vec![0u8; c.len()];
                            let n = c.read(&mut buf).unwrap();
                            buf.truncate(n);
                            if c.ppi == PayloadProtocolIdentifier::Dcep {
                                assert_eq!(buf, dcep_open("main-channel"));
                                s.write_sctp(
                                    &Bytes::from(vec![DCEP_ACK]),
                                    PayloadProtocolIdentifier::Dcep,
                                )
                                .unwrap();
                            } else {
                                let mut reply = b"echo:".to_vec();
                                reply.extend_from_slice(&buf);
                                s.write_sctp(
                                    &Bytes::from(reply),
                                    PayloadProtocolIdentifier::Binary,
                                )
                                .unwrap();
                            }
                        }
                    }
                }
                let _ = a.accept_stream();
                flush(a, &mut theirs, *h, &mut ep).unwrap();
            }
        });

        let (sender, mut events) = open(ours, "main-channel", 0);
        assert!(
            sender.send(b"syn".to_vec()),
            "queued before the channel opens"
        );
        async fn next(
            e: &mut tokio::sync::mpsc::UnboundedReceiver<DataEvent>,
        ) -> Option<DataEvent> {
            tokio::time::timeout(Duration::from_secs(5), e.recv())
                .await
                .unwrap()
        }
        assert_eq!(next(&mut events).await, Some(DataEvent::Open));
        assert_eq!(
            next(&mut events).await,
            Some(DataEvent::Message(b"echo:syn".to_vec()))
        );
        sender.send(b"sr".to_vec());
        assert_eq!(
            next(&mut events).await,
            Some(DataEvent::Message(b"echo:sr".to_vec()))
        );
    }
}
