// lib/screens/trip_mode_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../services/location_service.dart';
import '../services/ai_service.dart';
import '../services/api_keys.dart';

/// TripModeScreen
/// - Keep theme via `background` gradient passed from Home screen.
/// - Draw straight route line, sample intermediate points, reverse-geocode to get nearby city names,
///   query OpenWeather for each sample, color route by worst weather severity,
///   show origin/destination/city markers.
/// - Render AI suggestions as Markdown (so emojis, #, * are preserved).
class TripModeScreen extends StatefulWidget {
  final Gradient background;

  const TripModeScreen({Key? key, required this.background}) : super(key: key);

  @override
  State<TripModeScreen> createState() => _TripModeScreenState();
}

class _TripModeScreenState extends State<TripModeScreen> {
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();

  DateTime? _selectedDate;
  bool _loading = false;
  String? _aiSuggestions;
  String? _error;

  LatLng? _originCoords;
  LatLng? _destinationCoords;
  String? _originDisplay;
  String? _destinationDisplay;

  List<LatLng> _routePoints = [];
  List<_CityStop> _cityStops = []; // intermediate stops with weather
  Color _routeColor = Colors.greenAccent;

  // config: how many intermediate samples (including origin/destination -> N segments)
  static const int _samples = 5;

  // helpers
  final Distance _distanceCalculator = const Distance();

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Map OpenWeather description to severity (0 good, 1 moderate, 2 harsh)
  int _severityFromDesc(String desc) {
    final d = desc.toLowerCase();
    if (d.contains('thunder') || d.contains('tornado') || d.contains('hurricane') || d.contains('extreme')) {
      return 2;
    }
    if (d.contains('rain') || d.contains('snow') || d.contains('sleet') || d.contains('storm') || d.contains('shower')) {
      return 1;
    }
    // clear, clouds, mist -> treat as 0/1 depending on mist/haze
    if (d.contains('mist') || d.contains('haze') || d.contains('fog')) return 1;
    return 0;
  }

  Color _colorForSeverity(int s) {
    if (s >= 2) return Colors.redAccent;
    if (s == 1) return Colors.blueAccent;
    return Colors.greenAccent;
  }

  /// Fetch OpenWeather current weather at given lat/lon
  Future<Map<String, dynamic>> _fetchWeatherAt(LatLng point) async {
    final key = ApiKeys.openWeatherKey;
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=${point.latitude}&lon=${point.longitude}&units=metric&appid=$key',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Weather API ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Resolve place name to LatLng using geocoding; returns null on failure
  Future<LatLng?> _resolvePlaceToCoords(String place) async {
    try {
      final results = await locationFromAddress(place);
      if (results.isNotEmpty) {
        final r = results.first;
        return LatLng(r.latitude, r.longitude);
      }
    } catch (_) {}
    return null;
  }

  /// Reverse geocode coords to a nice place label (city, locality, country)
  Future<String> _reverseGeocodeLabel(LatLng p) async {
    try {
      final placemarks = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final parts = <String>[];
        if (pm.locality != null && pm.locality!.isNotEmpty) parts.add(pm.locality!);
        if (pm.subAdministrativeArea != null && pm.subAdministrativeArea!.isNotEmpty && !parts.contains(pm.subAdministrativeArea)) parts.add(pm.subAdministrativeArea!);
        if (pm.country != null && pm.country!.isNotEmpty) parts.add(pm.country!);
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}
    // fallback to coordinates string
    return '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}';
  }

  /// Start whole flow: resolve both places, sample intermediate points, fetch weather, reverse geocode, compute route color
  Future<void> _prepareRouteAndSuggestions({bool useMyLocationAsOrigin = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _aiSuggestions = null;
      _cityStops = [];
      _routePoints = [];
    });

    try {
      // Resolve origin
      if (useMyLocationAsOrigin) {
        final pos = await LocationService.getCurrentLocation();
        _originCoords = LatLng(pos.latitude, pos.longitude);
        _originDisplay = await _reverseGeocodeLabel(_originCoords!);
        _originCtrl.text = _originDisplay!;
      } else {
        final originText = _originCtrl.text.trim();
        if (originText.isEmpty) throw Exception('Origin is empty.');
        final oc = await _resolvePlaceToCoords(originText);
        if (oc == null) throw Exception('Could not find origin location.');
        _originCoords = oc;
        _originDisplay = originText;
      }

      // Resolve destination
      final destText = _destCtrl.text.trim();
      if (destText.isEmpty) throw Exception('Destination is empty.');
      final dc = await _resolvePlaceToCoords(destText);
      if (dc == null) throw Exception('Could not find destination location.');
      _destinationCoords = dc;
      _destinationDisplay = destText;

      // Build route points (straight line)
      _routePoints = List<LatLng>.generate(_samples + 1, (i) {
        final t = i / _samples;
        final lat = _lerp(_originCoords!.latitude, _destinationCoords!.latitude, t);
        final lng = _lerp(_originCoords!.longitude, _destinationCoords!.longitude, t);
        return LatLng(lat, lng);
      });

      // For each sample, fetch weather and a city label
      final List<_CityStop> stops = [];
      int worstSeverity = 0;

      for (final p in _routePoints) {
        try {
          final weatherJson = await _fetchWeatherAt(p);
          final desc = (weatherJson['weather'] as List?)?.isNotEmpty == true
              ? (weatherJson['weather'][0]['description'] ?? '')
              : (weatherJson['weather']?[0]?['main'] ?? '');
          final sev = _severityFromDesc(desc.toString());
          if (sev > worstSeverity) worstSeverity = sev;

          // reverse geocode (best-effort)
          final label = await _reverseGeocodeLabel(p);

          final stop = _CityStop(point: p, label: label, weatherDesc: desc.toString(), severity: sev);
          stops.add(stop);
        } catch (_) {
          // on failure, still add a minimal stop with unknown weather
          final label = await _reverseGeocodeLabel(p);
          final stop = _CityStop(point: p, label: label, weatherDesc: 'unknown', severity: 0);
          stops.add(stop);
        }
      }

      // Decide route color based on worst severity found
      _routeColor = _colorForSeverity(worstSeverity);
      _cityStops = stops;

      // Ask AI for suggestions (pass origin/destination/date)
      final aiResp = await AIService.getTripRecommendations(
        origin: _originDisplay ?? _originCtrl.text.trim(),
        destination: _destinationDisplay ?? _destCtrl.text.trim(),
        date: _selectedDate ?? DateTime.now(),
      );

      // Done
      setState(() {
        _aiSuggestions = aiResp;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  String _formatDistanceKm(LatLng a, LatLng b) {
    final meters = _distanceCalculator.as(LengthUnit.Meter, a, b);
    final kms = meters / 1000.0;
    return '${kms.toStringAsFixed(1)} km';
  }

  String _estimateDriveTime(LatLng a, LatLng b, {double avgKmh = 60.0}) {
    final meters = _distanceCalculator.as(LengthUnit.Meter, a, b);
    final hours = (meters / 1000.0) / avgKmh;
    final dur = Duration(minutes: (hours * 60).round());
    final h = dur.inHours;
    final m = dur.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  // UI helpers
  Widget _buildTopControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Trip Mode', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _originCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Origin',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _prepareRouteAndSuggestions(useMyLocationAsOrigin: true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              child: const Text('Use my location', style: TextStyle(color: Colors.black)),
            )
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _destCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Destination',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedDate == null ? 'Select trip date' : 'Date: ${DateFormat.yMMMd().format(_selectedDate!)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
              icon: const Icon(Icons.calendar_today),
              label: const Text('Pick date'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loading ? null : () => _prepareRouteAndSuggestions(useMyLocationAsOrigin: false),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Plan'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMapCard() {
    final center = _originCoords ?? _destinationCoords ?? LatLng(20.0, 77.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 320,
        child: FlutterMap(
          options: MapOptions(
  	  initialCenter: center,
  	  initialZoom: 6,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.weather',
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: _routeColor,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (_originCoords != null)
                  Marker(
                    point: _originCoords!,
                    width: 40,
                    height: 40,
                    // use child instead of builder to match versions
                    child: Column(
                      children: [
                        const Icon(Icons.circle, color: Colors.blueAccent, size: 10),
                        const SizedBox(height: 2),
                        Text(
                          _originDisplay ?? 'Origin',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        )
                      ],
                    ),
                  ),
                if (_destinationCoords != null)
                  Marker(
                    point: _destinationCoords!,
                    width: 40,
                    height: 40,
                    child: Column(
                      children: [
                        const Icon(Icons.flag, color: Colors.redAccent, size: 18),
                        const SizedBox(height: 2),
                        Text(
                          _destinationDisplay ?? 'Destination',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        )
                      ],
                    ),
                  ),
                // city stops
                ..._cityStops.map((s) {
                  return Marker(
                    point: s.point,
                    width: 36,
                    height: 36,
                    child: Tooltip(
                      message: '${s.label}\n${s.weatherDesc}',
                      child: Icon(Icons.location_city, color: _colorForSeverity(s.severity)),
                    ),
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripSummary() {
    if (_originCoords == null || _destinationCoords == null) return const SizedBox.shrink();

    final dist = _formatDistanceKm(_originCoords!, _destinationCoords!);
    final eta = _estimateDriveTime(_originCoords!, _destinationCoords!);
    return Card(
      color: Colors.white.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Distance', style: TextStyle(color: Colors.white70)),
              Text(dist, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(width: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Est. drive time', style: TextStyle(color: Colors.white70)),
              Text(eta, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Route status', style: TextStyle(color: Colors.white70)),
              Row(children: [
                Icon(Icons.circle, color: _routeColor, size: 12),
                const SizedBox(width: 6),
                Text(_routeColor == Colors.greenAccent ? 'Good' : (_routeColor == Colors.blueAccent ? 'Moderate' : 'Harsh'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ])
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _legendChip('Good', Colors.greenAccent),
        _legendChip('Rain / Fog', Colors.blueAccent),
        _legendChip('Severe', Colors.redAccent),
      ],
    );
  }

  Widget _legendChip(String label, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 12),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildAISuggestions() {
    if (_aiSuggestions == null) return const SizedBox.shrink();
    return Card(
      color: Colors.white.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: MarkdownBody(
          data: _aiSuggestions!,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white70, fontSize: 15),
            h1: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            h2: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            listBullet: const TextStyle(color: Colors.white70),
            code: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: widget.background),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopControls(),
                const SizedBox(height: 12),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                  ),
                const SizedBox(height: 12),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (!_loading) ...[
                  _buildTripSummary(),
                  const SizedBox(height: 10),
                  _buildWeatherLegend(),
                  const SizedBox(height: 12),
                  _buildMapCard(),
                  const SizedBox(height: 12),
                  _buildAISuggestions(),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// small helper to hold stop info
class _CityStop {
  final LatLng point;
  final String label;
  final String weatherDesc;
  final int severity;
  _CityStop({required this.point, required this.label, required this.weatherDesc, required this.severity});
}

