// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ok_http/ok_http.dart';

/// Repeated OkHttp requests using the same client setup as Tango Tango.
///
/// Each [OkHttpClient.send] hits the two original crash sites:
/// `OkHttpClient$Builder.writeTimeout` and `Headers.toMultimap`.
const String _label = String.fromEnvironment(
  'SOAK_LABEL',
  defaultValue: 'local',
);
const String _url = String.fromEnvironment(
  'SOAK_URL',
  defaultValue: 'https://example.com/',
);
const int _workers = int.fromEnvironment('SOAK_WORKERS', defaultValue: 4);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: SoakPage()),
  );
}

class SoakPage extends StatefulWidget {
  const SoakPage({super.key});

  @override
  State<SoakPage> createState() => _SoakPageState();
}

class _SoakPageState extends State<SoakPage> {
  DateTime _startedAt = DateTime.now();
  Timer? _uiTimer;
  OkHttpClient? _client;
  var _running = false;
  var _ok = 0;
  var _fail = 0;
  var _lastStatus = 0;
  var _lastHeaders = 0;
  var _lastError = '';

  int get _total => _ok + _fail;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid) {
        unawaited(start());
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    unawaited(stop());
    super.dispose();
  }

  Future<void> start() async {
    if (_running || _client != null) {
      return;
    }
    _log('starting url=$_url workers=$_workers');
    try {
      final client = OkHttpClient(
        configuration: const OkHttpClientConfiguration(
          connectTimeout: Duration(seconds: 60),
          readTimeout: Duration(seconds: 60),
          writeTimeout: Duration(seconds: 60),
        ),
      );
      _client = client;
      _startedAt = DateTime.now();
      _running = true;
      _log('running');
      for (var i = 0; i < _workers; i++) {
        unawaited(_worker(i, client));
      }
    } catch (error, stack) {
      _lastError = error.toString();
      _log('start failed: $error\n$stack');
    }
  }

  Future<void> stop() async {
    _running = false;
    _client?.close();
    _client = null;
  }

  Future<void> _worker(int id, OkHttpClient client) async {
    while (_running) {
      try {
        final response = await client.get(Uri.parse(_url));
        await response.bodyBytes;
        _ok++;
        _lastStatus = response.statusCode;
        _lastHeaders = response.headers.length;
        _lastError = '';
      } catch (error) {
        _fail++;
        _lastError = error.toString();
        _log('fail n=$_total error=$error');
      }
      if (id == 0 && _total > 0 && _total % 25 == 0) {
        _logSnapshot();
      }
    }
  }

  void _logSnapshot() {
    final elapsed = DateTime.now().difference(_startedAt).inSeconds;
    _log(
      'n=$_total ok=$_ok fail=$_fail status=$_lastStatus '
      'headers=$_lastHeaders elapsed=${elapsed}s',
    );
  }

  void _log(String message) => debugPrint('SOAK label=$_label $message');

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Scaffold(body: Center(child: Text('Android only')));
    }
    final elapsed = DateTime.now().difference(_startedAt);
    return Scaffold(
      appBar: AppBar(title: Text('OkHttp soak ($_label)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('URL: $_url'),
            Text('Running: $_running'),
            Text('Elapsed: ${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'),
            Text('OK: $_ok'),
            Text('Fail: $_fail'),
            Text('Last status: $_lastStatus'),
            Text('Last header count: $_lastHeaders'),
            if (_lastError.isNotEmpty) Text('Last error: $_lastError'),
          ],
        ),
      ),
    );
  }
}
