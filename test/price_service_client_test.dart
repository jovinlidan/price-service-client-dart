import 'dart:async';

import 'package:price_service_client/price_service_client.dart';
import 'package:price_service_sdk/price_service_sdk.dart';
import 'package:test/test.dart';

typedef DurationInMs = int;

// The endpoint is set to the price service endpoint.
// Please note that if you change it to a mainnet/testnet endpoint
// some tests might fail due to the huge response size of a request.
// i.e. requesting latest price feeds or vaas of all price ids.
const String kPriceServiceEndpoint = 'https://hermes.pyth.network';
const int kBatchSize = 10;

void main() {
  group('Test http endpoints', () {
    test('Get price feed (without verbose/binary) works', () async {
      final connection = PriceServiceConnection(kPriceServiceEndpoint);

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final priceFeeds = await connection.getLatestPriceFeeds(ids);

      expect(priceFeeds, isNotNull);
      expect(priceFeeds!.length, ids.length);

      for (final pf in priceFeeds) {
        expect(pf.id.length, 64); // 32-byte hex = 64 chars
        expect(pf, isA<PriceFeed>());
        expect(pf.getPriceUnchecked(), isA<Price>());
        expect(pf.getEmaPriceUnchecked(), isA<Price>());
        expect(pf.getMetadata(), isNull);
        expect(pf.getVAA(), isNull);
      }
    });

    test('Get price feed with verbose flag works', () async {
      final connection = PriceServiceConnection(
        kPriceServiceEndpoint,
        config: PriceServiceConnectionConfig(
          priceFeedRequestConfig: PriceFeedRequestConfig(verbose: true),
        ),
      );

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final priceFeeds = await connection.getLatestPriceFeeds(ids);
      expect(priceFeeds, isNotNull);
      expect(priceFeeds!.length, ids.length);

      for (final pf in priceFeeds) {
        expect(pf.getMetadata(), isA<PriceFeedMetadata>());
        expect(pf.getVAA(), isNull);
      }
    });

    test('Get price feed with binary flag works', () async {
      final connection = PriceServiceConnection(
        kPriceServiceEndpoint,
        config: PriceServiceConnectionConfig(
          priceFeedRequestConfig: PriceFeedRequestConfig(binary: true),
        ),
      );

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final priceFeeds = await connection.getLatestPriceFeeds(ids);
      expect(priceFeeds, isNotNull);
      expect(priceFeeds!.length, ids.length);

      for (final pf in priceFeeds) {
        expect(pf.getMetadata(), isNull);
        expect(pf.getVAA()?.isNotEmpty ?? false, isTrue);
      }
    });

    test('Get latest vaa works', () async {
      final connection = PriceServiceConnection(
        kPriceServiceEndpoint,
        config: PriceServiceConnectionConfig(
          priceFeedRequestConfig: PriceFeedRequestConfig(binary: true),
        ),
      );

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final vaas = await connection.getLatestVaas(ids);
      expect(vaas.isNotEmpty, isTrue);
      for (final vaa in vaas) {
        expect(vaa.isNotEmpty, isTrue);
      }
    });

    test('Get vaa works', () async {
      final connection = PriceServiceConnection(
        kPriceServiceEndpoint,
        config: PriceServiceConnectionConfig(
          priceFeedRequestConfig: PriceFeedRequestConfig(binary: true),
        ),
      );

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final publishTime10SecAgo = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 10;

      final result = await connection.getVaa(ids.first, publishTime10SecAgo);
      final vaa = result.vaa;
      final vaaPublishTime = result.publishTime;

      expect(vaa.isNotEmpty, isTrue);
      expect(vaaPublishTime >= publishTime10SecAgo, isTrue);
    });
  });

  group('Test websocket endpoints', () {
    test(
      'websocket subscription works without verbose and binary',
      () async {
        final connection = PriceServiceConnection(kPriceServiceEndpoint);

        final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
        expect(ids.isNotEmpty, isTrue);

        final counter = <String, int>{};
        var totalCounter = 0;

        await connection.subscribePriceFeedUpdates(ids, (pf) {
          expect(pf.id.length, 64);
          expect(pf.getMetadata(), isNull);
          expect(pf.getVAA(), isNull);

          counter[pf.id] = (counter[pf.id] ?? 0) + 1;
          totalCounter += 1;
        });

        // Wait for 30 seconds
        await Future.delayed(const Duration(milliseconds: 30000));
        connection.closeWebSocket();

        expect(totalCounter > 30, isTrue);

        for (final id in ids) {
          expect(counter.containsKey(id), isTrue);
          expect((counter[id] ?? 0) > 1, isTrue);
        }
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('websocket subscription works with verbose', () async {
      final connection = PriceServiceConnection(
        kPriceServiceEndpoint,
        config: PriceServiceConnectionConfig(
          priceFeedRequestConfig: PriceFeedRequestConfig(verbose: true),
        ),
      );

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final observed = <String>{};

      await connection.subscribePriceFeedUpdates(ids, (pf) {
        expect(pf.getMetadata(), isA<PriceFeedMetadata>());
        expect(pf.getVAA(), isNull);
        observed.add(pf.id);
      });

      await Future.delayed(const Duration(milliseconds: 20000));
      await connection.unsubscribePriceFeedUpdates(ids);

      for (final id in ids) {
        expect(observed.contains(id), isTrue);
      }
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('websocket subscription works with binary', () async {
      final connection = PriceServiceConnection(
        kPriceServiceEndpoint,
        config: PriceServiceConnectionConfig(
          priceFeedRequestConfig: PriceFeedRequestConfig(binary: true),
        ),
      );

      final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
      expect(ids.isNotEmpty, isTrue);

      final observed = <String>{};

      await connection.subscribePriceFeedUpdates(ids, (pf) {
        expect(pf.getMetadata(), isNull);
        expect(pf.getVAA()?.isNotEmpty ?? false, isTrue);
        observed.add(pf.id);
      });

      await Future.delayed(const Duration(milliseconds: 20000));
      connection.closeWebSocket();

      for (final id in ids) {
        expect(observed.contains(id), isTrue);
      }
    }, timeout: const Timeout(Duration(minutes: 1)));

    test(
      'websocket subscription works with allow out of order',
      () async {
        final connection = PriceServiceConnection(
          kPriceServiceEndpoint,
          config: PriceServiceConnectionConfig(
            priceFeedRequestConfig: PriceFeedRequestConfig(allowOutOfOrder: true, verbose: true),
          ),
        );

        final ids = (await connection.getPriceFeedIds()).sublist(0, kBatchSize);
        expect(ids.isNotEmpty, isTrue);

        final observedSlots = <int>[];

        await connection.subscribePriceFeedUpdates(ids, (pf) {
          final meta = pf.getMetadata();
          expect(meta, isNotNull);
          expect(pf.getVAA(), isNull);
          if (meta?.slot != null) observedSlots.add(meta!.slot!);
        });

        await Future.delayed(const Duration(milliseconds: 20000));
        connection.closeWebSocket();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
