// lib/screens/home_screen.dart
import 'trip_mode_screen.dart';
import 'dart:convert';
import '../services/api_keys.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// --- CONFIG: Replace with your OpenWeather API key ---
const String OPENWEATHER_API_KEY = ApiKeys.openWeatherKey;

/// Safe number conversion
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

/// Service layer for location handling
class LocationService {
  static Future<Position> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled.');

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions permanently denied.');
    }

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }
}

class WeatherHomeScreen extends StatefulWidget {
  final String? city;

  const WeatherHomeScreen({Key? key, this.city}) : super(key: key);

  @override
  State<WeatherHomeScreen> createState() => _WeatherHomeScreenState();
}

class _WeatherHomeScreenState extends State<WeatherHomeScreen> {
  bool _loading = true;
  bool _searching = false;
  bool _isCelsius = true;
  String? _locationQuery;
  Map<String, dynamic>? _weatherData;
  String? _error;

  int _selectedTab = 0; // 0 = Weather, 1 = Trip Mode

  final TextEditingController _searchController = TextEditingController();
  static const String _prefsLastLocation = 'last_location';

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsLastLocation);

      if (saved != null && saved.isNotEmpty) {
        _locationQuery = saved;
        _searchController.text = saved;
        await _fetchWeather(saved);
      } else {
        final pos = await LocationService.getCurrentLocation();
        final coords = '${pos.latitude},${pos.longitude}';
        _locationQuery = coords;
        await prefs.setString(_prefsLastLocation, coords);
        await _fetchWeather(coords);
      }
    } catch (e) {
      _error = e.toString();
      _locationQuery = 'New Delhi';
      await _fetchWeather('New Delhi');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchWeather(String queryOrCoords) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Uri uri;
      if (queryOrCoords.contains(',')) {
        // coords "lat,lon"
        final parts = queryOrCoords.split(',');
        uri = Uri.parse(
            'https://api.openweathermap.org/data/2.5/weather?lat=${parts[0]}&lon=${parts[1]}&appid=$OPENWEATHER_API_KEY&units=metric');
      } else {
        // city name
        uri = Uri.parse(
            'https://api.openweathermap.org/data/2.5/weather?q=$queryOrCoords&appid=$OPENWEATHER_API_KEY&units=metric');
      }

      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        throw Exception('Weather API error: ${resp.statusCode}');
      }

      final Map<String, dynamic> json = jsonDecode(resp.body);
      if (json['cod'] != 200) {
        throw Exception(json['message'] ?? 'Weather API error');
      }

      setState(() {
        _weatherData = json;
        _locationQuery = queryOrCoords;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLastLocation, queryOrCoords);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // Helpers
  Color _primaryColorForDesc(String desc) {
    final d = desc.toLowerCase();
    if (d.contains('rain') || d.contains('drizzle')) return Colors.blue.shade800;
    if (d.contains('snow')) return Colors.lightBlue.shade100;
    if (d.contains('cloud')) return Colors.blueGrey.shade600;
    if (d.contains('fog') || d.contains('mist')) return Colors.indigo.shade700;
    if (d.contains('clear') || d.contains('sun')) return Colors.lightBlue.shade400;
    return Colors.lightBlue.shade300;
  }

  Gradient _backgroundGradientForDesc(String desc) {
    final c = _primaryColorForDesc(desc);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [c.withOpacity(0.95), c.withOpacity(0.45)],
    );
  }

  String _formatLocalTime() {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(
          ((_weatherData!['dt'] as num).toInt() * 1000),
          isUtc: true);
      final offset = Duration(seconds: _weatherData!['timezone'] as int);
      final local = dt.add(offset);
      return DateFormat('EEEE, MMM d  h:mm a').format(local);
    } catch (_) {
      return DateFormat('EEEE, MMM d  h:mm a').format(DateTime.now());
    }
  }

  Widget _buildTopTabs(Color themeColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTabButton('Weather', 0, themeColor),
          _buildTabButton('Trip Mode', 1, themeColor),
        ],
      ),
    );
  }

  Widget _buildTabButton(String text, int index, Color themeColor) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(Color themeColor) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: Colors.white70),
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: (val) async {
                if (val.trim().isEmpty) return;
                setState(() => _searching = true);
                await _fetchWeather(val.trim());
                setState(() => _searching = false);
              },
            ),
          ),
        ),
        const SizedBox(width: 10.0),
        // Celsius/Fahrenheit toggle
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _toggleUnit('°C', true),
              _toggleUnit('°F', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleUnit(String label, bool celsius) {
    final active = _isCelsius == celsius;
    return GestureDetector(
      onTap: () => setState(() => _isCelsius = celsius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildMainCard(Color themeColor) {
    final main = _weatherData?['main'];
    final sys = _weatherData?['sys'];
    final weather = (_weatherData?['weather'] as List?)?.first;
    final wind = _weatherData?['wind'];

    final location = _weatherData?['name'] ?? 'Unknown';
    final country = sys?['country'] ?? '';
    final desc = weather?['description'] ?? '—';

    final tempC = _toDouble(main?['temp']);
    final temp = _isCelsius ? tempC : (tempC * 9 / 5) + 32;

    return Card(
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$location, $country',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4.0),
                      Text(_formatLocalTime(),
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                if (weather?['icon'] != null)
                  Image.network(
                    "http://openweathermap.org/img/wn/${weather['icon']}@2x.png",
                    width: 70,
                    height: 70,
                  ),
              ],
            ),
            const SizedBox(height: 12.0),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${temp.toStringAsFixed(1)}°',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 12.0),
                Text(desc,
                    style: const TextStyle(color: Colors.white70, fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(Color themeColor) {
    final main = _weatherData?['main'];
    final wind = _weatherData?['wind'];
    final clouds = _weatherData?['clouds'];

    final stats = [
      ['Feels like', '${_toDouble(main?['feels_like']).toStringAsFixed(1)}°', Icons.thermostat],
      ['Pressure', '${_toDouble(main?['pressure']).toStringAsFixed(0)} hPa', Icons.speed],
      ['Wind', '${_toDouble(wind?['speed']).toStringAsFixed(1)} m/s', Icons.air],
      ['Humidity', '${_toDouble(main?['humidity']).toStringAsFixed(0)}%', Icons.opacity],
      ['Clouds', '${_toDouble(clouds?['all']).toStringAsFixed(0)}%', Icons.cloud],
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats
          .map((s) => _SmallStatCard(
                title: s[0] as String,
                value: s[1] as String,
                icon: s[2] as IconData,
                color: themeColor.withOpacity(0.2),
                labelStyle:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ))
          .toList(),
    );
  }

  Widget _buildHourlyStrip(Color themeColor) {
    final tempC = _toDouble(_weatherData?['main']?['temp']);
    final t = _isCelsius ? tempC : (tempC * 9 / 5) + 32;

    DateTime now = DateTime.now();

    final items = List.generate(8, (i) {
      final hour = now.add(Duration(hours: i + 1));
      return _HourlyCard(time: DateFormat.Hm().format(hour), temp: t);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hourly Forecast',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 8.0),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (_, idx) => items[idx],
            separatorBuilder: (_, __) => const SizedBox(width: 8.0),
            itemCount: items.length,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final desc = (_weatherData?['weather']?[0]?['description']) ?? 'Clear';
    final themeColor = _primaryColorForDesc(desc);

    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(gradient: _backgroundGradientForDesc(desc)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  children: [
                    _buildTopTabs(themeColor),
                    const SizedBox(height: 8.0),
                    if (_selectedTab == 0) _buildSearchBar(themeColor),
                    if (_error != null) ...[
                      const SizedBox(height: 10.0),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.white70)),
                      ),
                    ]
                  ],
                ),
              ),
              Expanded(
                child: _selectedTab == 0
                    ? (_loading
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.white))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildMainCard(themeColor),
                                const SizedBox(height: 18.0),
                                _buildStatsRow(themeColor),
                                const SizedBox(height: 18.0),
                                _buildHourlyStrip(themeColor),
                              ],
                            ),
                          ))
                    : TripModeScreen(background: _backgroundGradientForDesc(desc)),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: () async {
                setState(() => _loading = true);
                try {
                  final pos = await LocationService.getCurrentLocation();
                  final coords = '${pos.latitude},${pos.longitude}';
                  await _fetchWeather(coords);
                } catch (e) {
                  setState(() => _error = e.toString());
                } finally {
                  setState(() => _loading = false);
                }
              },
              child: const Icon(Icons.my_location, color: Colors.blue),
            )
          : null,
    );
  }
}

/// Minimal hourly card
class _HourlyCard extends StatelessWidget {
  final String time;
  final double temp;

  const _HourlyCard({Key? key, required this.time, required this.temp})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white12, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(time, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8.0),
          const Icon(Icons.cloud, color: Colors.white70),
          const SizedBox(height: 8.0),
          Text('${temp.toStringAsFixed(1)}°',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SmallStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final TextStyle labelStyle;

  const _SmallStatCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.labelStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: labelStyle),
                const SizedBox(height: 6.0),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

