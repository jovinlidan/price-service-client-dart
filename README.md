# Pyth Client for Dart

A **Dart port of the [Pyth JavaScript SDK](https://github.com/pyth-network/pyth-crosschain/tree/main/price_service/client/js)**, originally developed by the **Pyth Data Association**.

This package allows Dart and Flutter developers to interact with the [Pyth Network](https://pyth.network), query price feeds, and work with web socketi wan.

---

## ✨ Features

- **HTTP API**
  - `getPriceFeedIds()` – list of available price IDs
  - `getLatestPriceFeeds(ids)` – latest price feeds (supports `verbose` / `binary`)
  - `getLatestVaas(ids)` – latest VAAs for feeds
  - `getVaa(id, publishTime)` – earliest VAA since a timestamp
- **WebSocket API**
  - Subscribe/unsubscribe to live feed updates
  - Auto-reconnect with **exponential backoff**
  - Heartbeat/timeout detection (Node/VM)
  - Resubscribe on reconnect
- **Configurable**
  - Timeouts, retry count (HTTP)
  - Verbose/binary price payloads
  - Optional logger (`logger` package)

---

## 🚀 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  price_service_client: ^0.1.0
```
