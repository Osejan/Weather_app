# 🌦️ Weather & Trip Planner App  

> *“Plan smarter journeys with live weather, AI-powered suggestions, and interactive maps — all in one app!”*  

---

![Flutter](https://img.shields.io/badge/Framework-Flutter-blue.svg)  
![License](https://img.shields.io/badge/License-MIT-green.svg)  
![API](https://img.shields.io/badge/API-OpenWeather%20%26%20OpenAI-orange.svg)  

---

## ✨ Overview  
The **Weather & Trip Planner App** is a Flutter-based mobile application designed to **simplify trip planning**.  
It combines **real-time weather insights**, **AI travel suggestions**, and **map-based route visualization** to give users a complete experience.  

Whether you want to check the weather before you travel 🌤️, visualize your route 🗺️, or get personalized AI tips 🤖 — this app has you covered.  

---

## 🚀 Features  

✅ **Real-time Weather Updates**  
- Fetches current & forecast weather data.  
- Highlights conditions on the trip route using color indicators (safe ☀️, cloudy 🌥️, stormy 🌩️).  

✅ **Interactive Map Integration**  
- Start point and destination shown on OpenStreetMap.  
- Route visualized with a straight line 📍➝📍.  
- Important cities marked along the journey.  

✅ **AI-Powered Travel Suggestions**  
- Uses OpenAI to recommend tips & highlights.  
- Suggestions enhanced with **headings (#)**, **emphasis (*)**, and **emojis**.  

✅ **Customizable Trips**  
- Select **origin**, **destination**, and **travel date**.  
- Saves preferences for easy reuse.  

✅ **Secure API Key Handling**  
- API keys stored safely in `api_keys.dart` (excluded from Git).  
- Example template provided: `api_keys.example.dart`.  

---

## 🛠️ Tech Stack  

- **Framework:** Flutter (Dart SDK ≥ 3.9.0)  
- **UI Toolkit:** Material Design + Custom Gradient Theme  
- **Mapping:** `flutter_map` + `latlong2` (OpenStreetMap)  
- **Location Services:** `geolocator`, `geocoding`  
- **Storage:** `shared_preferences`  
- **Networking:** `http`  
- **AI Integration:** OpenAI API  
- **Environment Management:** `flutter_dotenv`  

---

## 🔑 APIs Used  

1. **OpenWeatherMap API** 🌤️  
   - For real-time weather and forecasts.  
2. **OpenAI API** 🤖  
   - For generating smart trip recommendations.  
3. **OpenStreetMap (via flutter_map)** 🗺️  
   - For route visualization and marking cities.  

---

## ⚙️ Installation & Setup  

Clone the repository:  
```bash
git clone https://github.com/Osejan/Weather_app.git
cd Weather_app
