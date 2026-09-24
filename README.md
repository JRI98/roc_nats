# Connecting Roc to NATS (Experiment)

An experimental proof of concept exploring how to connect and communicate with a [NATS](https://nats.io/) messaging server from the [Roc](https://www.roc-lang.org/) programming language.

> [!NOTE]
> This project is **not** a full-featured or production-ready NATS client. It is a minimal, educational experiment exploring raw TCP communication and protocol framing with NATS using Roc's [`basic-cli`](https://github.com/roc-lang/basic-cli) platform.

## What This Explores

The experiment tests basic protocol interactions defined by the [NATS Protocol Specification](https://docs.nats.io/reference/reference-protocols/nats-protocol):

- **TCP Connection & Handshake:** Connects via raw TCP, receives the server's initial `INFO` message, sends a `CONNECT` command, and awaits `+OK`.
- **Publishing:** Tests sending both standard `PUB` and header-enabled `HPUB` messages.
- **Subscribing:** Tests basic subject subscriptions (`SUB`) and message receipt.
- **Message Framing:** Handles CRLF (`\r\n`) protocol delimiters, payload length parsing, and reading message payloads (`MSG` and `HMSG`).
- **Heartbeats:** Responds to incoming server `PING` requests with `PONG` to keep the connection alive.
- **Header Parsing:** Demonstrates parsing and serializing `NATS/1.0` headers into Roc data structures (`Dict(Str, Str)`).

## Prerequisites

- **[Roc](https://www.roc-lang.org/install):** Roc compiler installed and available in your `PATH`.
- **[Docker](https://www.docker.com/):** (Optional) Used by the `Makefile` to spin up a temporary local NATS server for testing.

## Running the Experiment

### Option 1: Using Docker (`make run`)

A helper `Makefile` is included to start a temporary NATS container on port `4222`, run the Roc code, and tear down the container when done:

```sh
make run
```

### Option 2: Against an Existing NATS Server

If you already have a local NATS server running on `127.0.0.1:4222`:

```sh
roc main.roc
```

## How It Works

1. **`handshake!`**: Reads the server's opening `INFO` payload, replies with a `CONNECT` command, and asserts `+OK`.
2. **`SUB` & `PUB`**: Subscribes to `test.>` and sends a test publication to `test.hello`.
3. **`loop!`**: Enters a simple event loop listening on the TCP stream, dispatching incoming messages (`MSG`/`HMSG`) and heartbeats (`PING`).

## References

- [NATS Protocol Documentation](https://docs.nats.io/reference/reference-protocols/nats-protocol)
- [Developing a NATS Client](https://docs.nats.io/reference/reference-protocols/nats-protocol/nats-client-dev)
- [NATS Protocol API Reference](https://docs.nats.io/reference/reference-protocols/nats_api_reference)
