import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';

http.Client createPlatformHttpClient() => IOClient(HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..idleTimeout = const Duration(seconds: 30)
  ..maxConnectionsPerHost = 6);
