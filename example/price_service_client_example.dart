// example.dart
import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logger/logger.dart';

import 'package:price_service_client/src/price_service_connection.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'endpoint',
      help: 'Endpoint URL for the price service, e.g. https://endpoint/example',
      valueHelp: 'URL',
      mandatory: true,
    )
    ..addOption(
      'price-ids',
      help: 'Space- or comma-separated price feed ids (hex, w/o 0x).',
      valueHelp: 'ID',
      mandatory: true,
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  late ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    _printUsageAndExit(parser, error: e.toString());
  }

  if (args['help'] as bool) {
    _printUsageAndExit(parser);
  }

  final endpoint = args['endpoint'] as String;
  final priceIds = (args['price-ids'] as String).split(',').toList();

  if (priceIds.isEmpty) {
    _printUsageAndExit(parser, error: 'At least one --price-ids value is required.');
  }

  final logger = Logger(level: Level.trace, printer: SimplePrinter(colors: true));

  final connection = PriceServiceConnection(
    endpoint,
    config: PriceServiceConnectionConfig(
      logger: logger,
      priceFeedRequestConfig: PriceFeedRequestConfig(binary: true),
      timeout: const Duration(milliseconds: 5000),
      httpRetries: 3,
    ),
  );

  print(priceIds.runtimeType);

  final priceFeeds = await connection.getLatestPriceFeeds(priceIds);

  logger.i('Latest price feeds: $priceFeeds');
  if (priceFeeds != null && priceFeeds.isNotEmpty) {
    final p = priceFeeds.first.getPriceNoOlderThan(60);
    logger.i('First feed getPriceNoOlderThan(60): $p');
  }

  logger.i('Subscribing to price feed updates...');

  await connection.subscribePriceFeedUpdates(priceIds, (priceFeed) {
    final latest = priceFeed.getPriceNoOlderThan(60);
    logger.i('Current price for ${priceFeed.id}: ${latest?.toJson()}');
    logger.i('VAA: ${priceFeed.getVAA()}');
  });

  await Future.delayed(const Duration(minutes: 10));

  logger.i('Unsubscribing from price feed updates.');
  await connection.unsubscribePriceFeedUpdates(priceIds);

  connection.closeWebSocket();
}

Never _printUsageAndExit(ArgParser parser, {String? error}) {
  if (error != null) {
    stderr.writeln('Error: $error\n');
  }
  stdout.writeln('Usage: dart run example/price_service_client_example.dart [options]');
  stdout.writeln(parser.usage);
  exit(error == null ? 0 : 64); // 64 = EX_USAGE
}
