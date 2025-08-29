String makeWebsocketUrl(String endpoint) {
  final uri = Uri.parse(endpoint);
  final useHttps = uri.scheme == 'https';
  final wsScheme = useHttps ? 'wss' : 'ws';

  final wsUri = uri.replace(scheme: wsScheme);
  return wsUri.toString();
}

String removeLeading0xIfExists(String id) {
  return id.startsWith('0x') ? id.substring(2) : id;
}
