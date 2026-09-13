// lib/main.dart (debug helper)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

const String STATIC_LOGIN_ID = 'UPICSTE10';
const double OFFICE_LAT = 26.8652268;
const double OFFICE_LNG = 81.0082141;
const double GEOFENCE_RADIUS_METERS = 60.0;
class AppUrl { static const baseApi = 'http://172.20.10.6/cispu26Nov/api'; static String event() => '$baseApi/event'; }

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(home: const DebugScreen(), debugShowCheckedModeBanner: false);
  }
}

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});
  @override State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  Position? _pos;
  String _perm = 'unknown';
  String _lastMsg = '-';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionState();
  }

  Future<void> _checkPermissionState() async {
    final p = await Geolocator.checkPermission();
    setState(() { _perm = p.toString(); });
  }

  Future<void> _requestPermission() async {
    final p = await Geolocator.requestPermission();
    setState(() { _perm = p.toString(); });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permission: $p')));
  }

  Future<void> _getPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location service not enabled')));
        setState(() => _lastMsg = 'Location service disabled');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(const Duration(seconds: 6));
      setState(() { _pos = pos; _lastMsg = 'Got pos'; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pos: ${pos.latitude}, ${pos.longitude}')));
    } catch (e) {
      setState(() => _lastMsg = 'Get pos failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Get pos failed: $e')));
    }
  }

  Future<void> _send(String eventType, {Position? posOverride}) async {
    if (_sending) return;
    setState(() { _sending = true; });
    final pos = posOverride ?? _pos;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No position — cannot send')));
      setState(() { _sending = false; _lastMsg = 'No pos'; });
      return;
    }

    final payload = {
      'loginid': STATIC_LOGIN_ID,
      'event_type': eventType,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy': pos.accuracy ?? 0.0,
      'device_time': DateTime.now().toIso8601String(),
      'source': 'gps'
    };

    final hasNet = await InternetConnectionChecker().hasConnection;
    if (!hasNet) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No internet')));
      setState(() { _sending = false; _lastMsg = 'No internet'; });
      return;
    }

    try {
      final url = Uri.parse(AppUrl.event());
      debugPrint('POST -> $url\n$payload');
      final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 10));
      debugPrint('RESP ${resp.statusCode} : ${resp.body}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status ${resp.statusCode}')));
      setState(() { _lastMsg = 'Sent ${resp.statusCode}'; });
    } catch (e) {
      debugPrint('Send error $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send error: $e')));
      setState(() { _lastMsg = 'Send error: $e'; });
    } finally {
      setState(() { _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = _pos?.latitude?.toStringAsFixed(6) ?? '-';
    final lng = _pos?.longitude?.toStringAsFixed(6) ?? '-';
    final dist = (_pos == null) ? '-' : (Geolocator.distanceBetween(OFFICE_LAT, OFFICE_LNG, _pos!.latitude, _pos!.longitude).toStringAsFixed(1) + ' m');
    final inside = (dist != '-' && double.tryParse(dist.split(' ').first) != null && double.parse(dist.split(' ').first) <= GEOFENCE_RADIUS_METERS);
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Geo Attendance')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Permission: $_perm'),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(onPressed: _requestPermission, child: const Text('Request Permission')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _getPosition, child: const Text('Get Position')),
          ]),
          const SizedBox(height: 12),
          Text('Position: $lat , $lng'),
          Text('Distance to office: $dist'),
          Text('Inside?: ${inside ? "YES" : "NO"}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ElevatedButton(onPressed: () => _send('IN'), child: const Text('Send IN (use last pos)')),
            ElevatedButton(onPressed: () => _send('OUT'), child: const Text('Send OUT (use last pos)')),
            // ElevatedButton(onPressed: () async {
            //   // simulate IN using office coords (force success)
            //   final fake = Position(latitude: OFFICE_LAT, longitude: OFFICE_LNG, timestamp: DateTime.now(), accuracy: 1, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0);
            //   await _send('IN', posOverride: fake);
            // }, child: const Text('Simulate IN (office coords)')),
            // ElevatedButton(onPressed: () async {
            //   final fake = Position(latitude: OFFICE_LAT + 0.01, longitude: OFFICE_LNG + 0.01, timestamp: DateTime.now(), accuracy: 1, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0);
            //   await _send('OUT', posOverride: fake);
            // }, child: const Text('Simulate OUT (far)')),
          ]),
          const SizedBox(height: 12),
          Text('Last message: $_lastMsg'),
        ]),
      ),
    );
  }
}
