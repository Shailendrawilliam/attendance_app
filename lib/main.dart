import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
 import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:attendance_app/model/attendance_response.dart';
import 'package:attendance_app/res/app_url.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  runApp(const MaterialApp(home: AttendanceScreen()));
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {

  final double geofenceRadius = 60.0;
    Position? _officeLocation ;
  Position? _currentPosition;
  double _distance = 0.0;
  String _status = "UNKNOWN";
  String loginid = "UNKNOWN";
  bool _isTracking = false;

  List<Map<String, dynamic>> _logs = [];
  int _totalMilliseconds = 0;
  Timer? _uiTimer;
  StreamSubscription<Position>? _positionStream;

  Timer? _flushTimer;
  bool _isSending = false;


  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _setOfficeLocation();
    _loadLoginId();
    _startQueueFlusher();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _uiTimer?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
   }

  Future<void> _loadLoginId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      loginid = prefs.getString('loginid') ?? '';
    });
  }

  Future<void> _saveLoginId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loginid', id);
    setState(() => loginid = id);
  }

  Future<void> _setOfficeLocation1() async {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _officeLocation = position;
      _logs.clear();
      _totalMilliseconds = 0;
      _status = "OUTSIDE";
    });
    _startLocationUpdates();
  }

  Future<void> _setOfficeLocation() async {
    const double staticOfficeLat = 26.865163;
    const double staticOfficeLng = 81.008260;

    setState(() {
      _officeLocation = Position(
        latitude: staticOfficeLat,
        longitude: staticOfficeLng,
        timestamp: DateTime.now(),
        accuracy: 1,
        altitude: 0,
        heading: 0,
        floor: null,
        speed: 0,
        speedAccuracy: 0, altitudeAccuracy: 1,
        headingAccuracy: 0.0,
        isMocked: false,
      );

      _logs.clear();
      _totalMilliseconds = 0;
      _status = "OUTSIDE";

    });

    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    if (_isTracking) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      setState(() {
        _currentPosition = position;
      });

      if (_officeLocation != null) {
        double dist = Geolocator.distanceBetween(
          _officeLocation!.latitude,
          _officeLocation!.longitude,
          position.latitude,
          position.longitude,
        );

        setState(() {
          _distance = dist;
        });

        _checkGeofenceLogic(dist);
      }
    });

    setState(() => _isTracking = true);
  }

  void _checkGeofenceLogic(double distance) {
    bool isInside = distance <= geofenceRadius;
    DateTime now = DateTime.now();

    if (isInside && _status != "INSIDE") {
      setState(() {
        _status = "INSIDE";
        _logs.insert(0, {"type": "IN", "time": now});
      });
      _startUiTimer();

      sendAttendance('IN');
    } else if (!isInside && _status == "INSIDE") {
      setState(() {
        _status = "OUTSIDE";
        _logs.insert(0, {"type": "OUT", "time": now});
      });
      _stopUiTimer();
      _calculateSessionTime();
      sendAttendance('OUT');
    } else
    {


    }
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  void _stopUiTimer() {
    _uiTimer?.cancel();
  }

  void _calculateSessionTime() {
    if (_logs.length >= 2) {
      DateTime outTime = _logs[0]['time'];
      DateTime inTime = _logs[1]['time'];
      int sessionMs = outTime.difference(inTime).inMilliseconds;
      setState(() {
        _totalMilliseconds += sessionMs;
      });
    }
  }

  String get formattedTotalTime {
    int currentSession = 0;
    if (_status == "INSIDE" && _logs.isNotEmpty) {
      currentSession = DateTime.now().difference(_logs[0]['time']).inMilliseconds;
    }
    int total = _totalMilliseconds + currentSession;
    int hours = (total / (1000 * 60 * 60)).floor();
    int minutes = ((total / (1000 * 60)) % 60).floor();
    int seconds = ((total / 1000) % 60).floor();
    return "${hours}h ${minutes}m ${seconds}s";
  }

  void sendAttendance( eventType ) async {



    String? lang = 'en';//await userPreferences.fetchLang();
    print("starting api");
    bool result = await InternetConnectionChecker().hasConnection;
    if (result == true) {

      var request = jsonEncode({

        "id": loginid,
        "loginid": loginid,
        "event_type": eventType,
        "latitude": _currentPosition?.latitude ?? _officeLocation?.latitude ?? 0.0,
        "longitude": _currentPosition?.longitude ?? _officeLocation?.longitude ?? 0.0,
        "accuracy": _currentPosition?.accuracy ?? 0.0,
        "device_time": DateTime.now().toIso8601String(),
        "source": "gps"

      });
      try {
        await http.post(Uri.parse(AppUrl.event),
            // AppUrl.getAppVersion),
            headers: {
              'Content-Type': 'application/json',
            },
            body: request)
            .then((response) async {
          var data = json.decode(response.body.replaceAll("ï»¿", ""));

          var contentResponse = AttendanceResponse.fromJson(data);
          if (contentResponse != null) {
            print("api success");
            Fluttertoast.showToast(
              msg: 'Location updated success',
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.BOTTOM,
            );
          }
        });
      } catch (error) {
        print("api errr $error");
        Fluttertoast.showToast(
          msg: '$error',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } else {
      Fluttertoast.showToast(
        msg: 'No Internet',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
      print("api errr no internet");
    }
  }

  Future<bool> _postEvent(Map<String, dynamic> payload) async {
    if (_isSending) return false;
    _isSending = true;
    try {
      final resp = await http.post(
        Uri.parse(AppUrl.event),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));
      _isSending = false;
      return (resp.statusCode >= 200 && resp.statusCode < 300);
    } catch (e) {
      _isSending = false;
      print(e);
      Fluttertoast.showToast(
        msg: "$e",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
      print('No internet');

      return false;
    }
  }


  Future<void> _flushQueueOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'attendance_event_queue';
    final q = prefs.getStringList(key) ?? [];
    if (q.isEmpty) return;

    final List<String> remaining = [];
    for (final s in q) {
      try {
        final Map<String, dynamic> obj = jsonDecode(s);
        final success = await _postEvent(obj);
        if (!success){

          remaining.add(s);}
        else {

        }
      } catch (e) {
        remaining.add(s);
        Fluttertoast.showToast(
          msg: "$e",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    }
    await prefs.setStringList(key, remaining);
  }

  void _startQueueFlusher() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _flushQueueOnce();
    });
    // try immediately
    _flushQueueOnce();
  }

  // ---------------- UI ----------------

  void _showLoginIdDialog() {
    final controller = TextEditingController(text: loginid);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Login ID'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'loginid'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final v = controller.text.trim();
              if (v.isNotEmpty) {
                await _saveLoginId(v);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Geo Attendance Flutter"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _showLoginIdDialog,
            tooltip: 'Set loginid (currently saved)',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Card(
              color: _status == "INSIDE" ? Colors.green[100] : Colors.red[100],
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text("STATUS: $_status",
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _status == "INSIDE" ? Colors.green[800] : Colors.red[800])),
                    const SizedBox(height: 10),
                    Text(formattedTotalTime,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    const Text("Total Hours Today"),
                    const SizedBox(height: 8),
                    Text("loginid: ${loginid.isNotEmpty ? loginid : '(not set, using fallback)'}",
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text("Distance", style: TextStyle(color: Colors.grey)),
                    Text("${_distance.toStringAsFixed(1)} m",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text("Radius Limit", style: TextStyle(color: Colors.grey)),
                    Text("${geofenceRadius.toInt()} m",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_officeLocation == null)
              ElevatedButton.icon(
                onPressed: _setOfficeLocation,
                icon: const Icon(Icons.location_on),
                label: const Text("Set Current Location as Office"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
              )
            else
              Text(
                "Office Location Set ✅\nLat: ${_officeLocation!.latitude.toStringAsFixed(4)}\nLng: ${_officeLocation!.longitude.toStringAsFixed(4)}",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            const Divider(height: 40),
            const Align(alignment: Alignment.centerLeft, child: Text("Activity Logs:", style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return ListTile(
                    leading: Icon(
                      log['type'] == "IN" ? Icons.login : Icons.logout,
                      color: log['type'] == "IN" ? Colors.green : Colors.red,
                    ),
                    title: Text(log['type'] == "IN" ? "Entered Office" : "Left Office"),
                    trailing: Text(DateFormat('hh:mm:ss a').format(log['time'])),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
