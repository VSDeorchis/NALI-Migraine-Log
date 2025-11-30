# Weather Correlation Feature - Implementation Guide

## Overview
The weather correlation feature has been successfully integrated into your Headway migraine tracking app. This feature uses the **Open-Meteo API** (completely free, no registration required) to automatically fetch historical weather data for each migraine entry and provides comprehensive analytics to help identify weather-related triggers.

## What Was Implemented

### 1. **WeatherService** (`Shared/Services/WeatherService.swift`)
- Fetches historical weather data from Open-Meteo API
- No API key required - completely free
- Retrieves:
  - Temperature (°F)
  - Barometric pressure (hPa)
  - 24-hour pressure change calculation
  - Precipitation
  - Cloud cover
  - Weather conditions with codes
- Provides weather icons using SF Symbols
- Includes error handling for network issues

### 2. **LocationManager** (`Shared/Services/LocationManager.swift`)
- Manages user location for weather data
- Requests location permission on first launch
- Caches recent location (1 hour) to minimize battery usage
- Handles authorization states gracefully
- Falls back gracefully if location is denied

### 3. **Core Data Updates**
Added weather attributes to `MigraineEvent`:
- `weatherTemperature` - Temperature in Fahrenheit
- `weatherPressure` - Barometric pressure in hPa
- `weatherPressureChange24h` - 24-hour pressure change (key metric!)
- `weatherCondition` - Human-readable condition (e.g., "Clear", "Rain")
- `weatherIcon` - SF Symbol name for display
- `weatherPrecipitation` - Rainfall amount
- `weatherCloudCover` - Cloud coverage percentage
- `weatherCode` - WMO weather code
- `weatherLatitude/Longitude` - Location coordinates
- `hasWeatherData` - Boolean flag for data availability

### 4. **Automatic Weather Fetching**
Modified `MigraineViewModel.addMigraine()`:
- Automatically fetches weather data when saving a new migraine
- Runs asynchronously to not block the UI
- Gracefully handles errors (location denied, network issues)
- Logs detailed information for debugging

### 5. **Visual Enhancements**

#### **MigraineRowView** - Weather Icons in Log Entries
Each migraine entry now shows:
- Weather icon with color coding:
  - ☀️ Yellow for clear/sunny
  - 🌤️ Orange for partly cloudy
  - ☁️ Gray for cloudy
  - 🌧️ Blue for rain
  - ⛈️ Purple for thunderstorms
  - ❄️ Cyan for snow
- Temperature display
- Pressure change indicator with color coding:
  - 🟢 Green: Stable (< 2 hPa change)
  - 🟠 Orange: Moderate (2-5 hPa change)
  - 🔴 Red: Significant (> 5 hPa change)

#### **WeatherCorrelationView** - Comprehensive Analytics
New analytics screen accessible from Statistics tab showing:

1. **Weather Data Coverage**
   - Total migraines tracked
   - Migraines with weather data
   - Coverage percentage

2. **Barometric Pressure Changes Chart**
   - Bar chart showing 24-hour pressure changes before each migraine
   - Color-coded by severity (green/orange/red)
   - Legend explaining pressure change ranges
   - **Key insight**: Many migraine sufferers are sensitive to rapid pressure changes

3. **Weather Conditions Distribution**
   - Pie chart showing weather conditions during migraines
   - Identifies most common weather patterns

4. **Temperature Correlation**
   - Bar chart grouping migraines by temperature ranges
   - Helps identify temperature sensitivity

5. **Precipitation Correlation**
   - Simple comparison: migraines with rain vs. without
   - Identifies rain as a potential trigger

6. **Key Insights Section**
   - **Pressure Sensitivity**: Automatic calculation showing correlation strength
     - High (≥50%): Strong correlation with pressure changes
     - Moderate (30-50%): Moderate correlation
     - Low (<30%): Weak correlation
   - **Most Common Weather**: Shows which weather condition appears most often
   - **Temperature Pattern**: Average temperature during migraines

### 6. **Location Permissions**
Updated `Info.plist` with privacy descriptions:
- `NSLocationWhenInUseUsageDescription`: Explains why location is needed
- User-friendly message about weather correlation benefits

**New in v2.0**:
- Location services toggle added to initial disclaimer screen
- Users can enable/disable location services during onboarding
- Location permission requested immediately after accepting disclaimer (if enabled)

### 7. **Settings Integration**
**New Weather Tracking Section**:
- Real-time location authorization status display
  - 🟢 Green: Enabled
  - 🔴 Red: Disabled
  - 🟠 Orange: Not Set
- Smart action button:
  - "Enable" - Requests permission if not determined
  - "Open Settings" - Deep links to iOS Settings if denied
  - "Enabled" - Shows current status if authorized
- Helpful description with weather icon explaining benefits
- One-tap access to enable/manage location services

### 8. **Bulk Weather Backfill** (New in v2.1)
**Retroactive Weather Data Collection**:
- Fetch weather data for all past migraine entries
- Settings → Backfill Weather Data section
- Shows count of entries without weather data
- Progress indicator during bulk fetch
- Uses Open-Meteo Archive API (supports data back to 1940)
- Automatically saves after each fetch to prevent data loss
- 0.5 second delay between requests to be API-friendly

**How It Works**:
1. Go to Settings → Backfill Weather Data
2. See count of entries missing weather data
3. Tap "Start" to begin bulk fetch
4. Progress updates in real-time
5. Results summary when complete

### 9. **Manual Location Override** (New in v2.1)
**Custom Location for Weather Data**:
- Edit weather location for individual migraine entries
- Useful when traveling or logging migraines from different locations
- Two options:
  - **Use Current Location**: Fetches weather for your current GPS location
  - **Custom Coordinates**: Enter latitude/longitude manually
- Validates coordinates (lat: -90 to 90, lon: -180 to 180)
- Shows existing weather data before refresh
- Updates weather data with new location

**Access Methods**:
- **From Detail View**: Tap "Edit" button next to weather data
- **From Detail View (No Weather)**: Tap "Fetch" → "Custom Location"
- **After Fetch**: Weather data updates immediately

### 10. **App Integration**
- LocationManager initialized at app startup
- Location permission requested during onboarding (if user opts in)
- Location permission can be managed anytime in Settings
- WeatherService available throughout the app
- New "Weather Correlation" button in Statistics view
- Weather location editor available for all migraine entries

## How It Works

### Initial Setup (First Launch):
1. User sees disclaimer screen with two options:
   - **Enable iCloud Sync**: For device synchronization
   - **Enable Location Services**: For weather tracking
2. User can toggle location services on/off before accepting
3. If enabled, location permission is requested immediately after accepting
4. If disabled or denied, app works normally without weather data

### When a User Logs a Migraine:
1. User fills out the migraine form and taps "Save"
2. App saves the migraine to Core Data
3. **Automatically** (in background):
   - Gets user's current location (if permitted)
   - Fetches historical weather data for the migraine's start time
   - Retrieves data from 24 hours before to 1 hour after
   - Calculates 24-hour pressure change
   - Saves all weather data to the migraine entry
4. Weather icon and data appear in the log entry

### When Viewing Analytics:
1. User taps "Weather Correlation" in Statistics tab
2. App analyzes all migraines with weather data
3. Generates charts and insights
4. Calculates correlation percentages
5. Provides actionable insights

### Backfilling Weather Data (New in v2.1):
1. User goes to Settings → Backfill Weather Data
2. App shows count of entries without weather data
3. User taps "Start" to begin bulk fetch
4. App fetches weather for each entry (0.5s delay between requests)
5. Progress updates in real-time
6. Results summary shows success/failure counts
7. All historical entries now have weather data for analysis

### Manual Location Override (New in v2.1):
1. User opens a migraine entry in detail view
2. Taps "Edit" button next to weather data (or "Fetch" → "Custom Location" if no data)
3. Chooses between:
   - **Use Current Location**: Automatically uses GPS
   - **Custom Coordinates**: Manually enters lat/lon
4. Taps "Fetch Weather Data"
5. Weather data updates with new location
6. Useful for travel or when location changed since logging

## Key Features

### ✅ **No Registration Required**
- Open-Meteo API is completely free
- No API keys needed
- No rate limits for reasonable use
- No attribution required (though appreciated)

### ✅ **Privacy-Focused**
- Location only requested when needed
- Can deny location and app still works
- Weather data stored locally in Core Data
- No data sent to third parties

### ✅ **Automatic & Seamless**
- Weather data fetched automatically
- No user action required
- Graceful error handling
- Works offline with cached location

### ✅ **Scientifically Relevant**
- 24-hour pressure change is a known migraine trigger
- Temperature, humidity, and weather patterns matter
- Helps identify personal trigger patterns
- Provides actionable insights

## Usage Tips

### For Best Results:
1. **Enable Location Services During Onboarding**: Toggle on during first launch
2. **Or Enable Later in Settings**: Go to Settings → Weather Tracking → Enable
3. **Backfill Historical Data**: Use Settings → Backfill Weather Data for past entries
4. **Log Migraines Promptly**: More accurate weather correlation
5. **Review Analytics Regularly**: Check "Weather Correlation" tab monthly
6. **Look for Patterns**: Pay attention to pressure change insights
7. **Share with Doctor**: Export data showing weather correlations

### Managing Location Access:
- **First Time**: Toggle "Enable Location Services" in disclaimer screen
- **Change Later**: Settings → Weather Tracking section
- **If Denied**: Tap "Open Settings" button to enable in iOS Settings
- **Check Status**: Green = Enabled, Red = Disabled, Orange = Not Set

### iOS 26 Location Permissions (New Privacy Model):
- **"When I Share" is the Standard**: iOS 26 defaults to "When I Share" mode for all apps
- **How It Works**: iOS will ask "Allow Headway to use your location?" each time you save a migraine
- **Your Action**: Simply tap "Allow Once" when prompted - weather data is automatically fetched
- **This Is Normal**: This is Apple's new privacy-first approach, not a limitation
- **Weather Still Works**: Full weather tracking and correlation analysis works perfectly
- **No Setup Needed**: No need to change settings - just approve when saving entries
- **Bulk Backfill**: Manual fetch per entry recommended (see "Editing Weather Location" below)

### Backfilling Historical Data:
- **When to Use**: After enabling location services for the first time
- **How**: Settings → Backfill Weather Data → Start
- **What It Does**: Fetches weather for all entries without data
- **Time**: ~0.5 seconds per entry (100 entries = ~50 seconds)
- **Data Range**: Works for dates back to 1940
- **Location**: Uses current location or stored location from entry

### Editing Weather Location:
- **When to Use**: Traveling, different location than current, incorrect data
- **How**: Open migraine detail → Tap "Edit" next to weather data
- **Options**: Current GPS location or manual coordinates
- **Validation**: Ensures coordinates are valid (lat: -90 to 90, lon: -180 to 180)
- **Result**: Weather data refreshes with new location

### Understanding Pressure Changes:
- **< 2 hPa**: Stable, unlikely to trigger
- **2-5 hPa**: Moderate change, may trigger sensitive individuals
- **> 5 hPa**: Significant change, common trigger
- **Rising vs. Falling**: Some people are more sensitive to one direction

## Technical Details

### Open-Meteo API Endpoint:
```
https://archive-api.open-meteo.com/v1/archive
```

### Parameters Used:
- `latitude`, `longitude`: User location
- `start_date`, `end_date`: Migraine date ±24 hours
- `hourly`: temperature_2m, surface_pressure, precipitation, cloudcover, weathercode
- `temperature_unit`: fahrenheit
- `precipitation_unit`: inch
- `timezone`: auto

### Weather Codes (WMO):
- 0: Clear sky
- 1-3: Partly cloudy to overcast
- 45, 48: Fog
- 51-67: Drizzle to freezing rain
- 71-86: Snow and snow showers
- 95-99: Thunderstorms

## Recent Enhancements (v2.1)

### ✅ Implemented:
1. **Bulk Weather Backfill**: Retroactively fetch weather for all past entries
2. **Manual Location Override**: Edit weather location for individual entries
3. **Custom Coordinates**: Enter lat/lon manually for precise location
4. **Progress Tracking**: Real-time progress during bulk operations
5. **Enhanced Detail View**: Weather data section with edit capability
6. **Menu Options**: Multiple ways to fetch weather (current location, custom location)

## Future Enhancements (Optional)

### Potential Additions:
1. **Weather Alerts**: Notify when pressure is changing rapidly
2. **Forecast Integration**: Predict migraine risk based on forecast
3. **Humidity Tracking**: Add humidity as another data point
4. **Wind Speed**: Some people are sensitive to wind
5. **Moon Phase**: Controversial but some patients report correlation
6. **Export Weather Data**: Include in PDF reports
7. **Trigger Prediction**: ML model to predict migraines based on weather
8. **Location History**: Remember frequently used locations for quick selection

## Troubleshooting

### If Weather Data Isn't Appearing:
1. **iOS 26 "When I Share" Mode**: Make sure you tap "Allow Once" when iOS asks for location
2. **Check internet connection** (weather API requires network)
3. **Wait 10-15 seconds** - weather fetches asynchronously in background
4. **Check console logs** for error messages (look for 🌤️ and 📍 emojis)
5. **Verify date** is not too far in the past (API supports back to 1940)
6. **On simulator**: Set custom location via Features → Location menu
7. **Try manual fetch**: Open migraine detail → Tap "Fetch Weather" button
8. **Use custom coordinates**: If GPS fails, manually enter lat/lon

### iOS 26 Location Permission Behavior:
- **"When I Share" is Normal**: This is the standard iOS 26 permission model
- **Permission Dialog Each Time**: iOS will ask for location when you save a migraine - this is expected
- **Just Tap "Allow Once"**: Weather data will be fetched automatically
- **No Need to Change Settings**: The app works perfectly with "When I Share" mode
- **Bulk Backfill Limitation**: Use manual fetch per entry instead (see below)
- **Location Request Timeout**: Requests timeout after 10 seconds to prevent hangs

### If Location Permission Denied:
- App will still work for logging migraines
- Weather data won't be collected automatically
- You can still use manual fetch with custom coordinates (no permission needed)
- To re-enable: Settings > Privacy > Location Services > Headway

### If API Fails:
- Error is logged but app continues normally
- Migraine is still saved without weather data
- **Can manually retry**: Open migraine detail → Tap "Fetch" button
- **Try custom location**: Use different coordinates if current location fails
- **Bulk backfill**: Use Settings → Backfill Weather Data to retry all at once

### If App Crashes on Save:
- **Fixed**: Core Data model now includes all weather attributes
- **Fixed**: Automatic merging temporarily disabled during saves
- **Fixed**: Weather icon validation prevents invalid SF Symbol names
- If still crashing: Clean build (⌘⇧K) and reset simulator

## Testing Checklist

### Core Features:
- [x] WeatherService fetches data successfully
- [x] LocationManager requests permission with 10-second timeout
- [x] Weather data saves to Core Data without deadlocks
- [x] Weather icons appear in log entries (validated SF Symbols)
- [x] Pressure change colors display correctly
- [x] WeatherCorrelationView renders charts
- [x] Insights calculate correctly
- [x] App handles location denial gracefully
- [x] App handles network errors gracefully
- [x] No crashes when no weather data available
- [x] Core Data model includes all weather attributes
- [x] iOS and Watch apps work independently
- [x] Automatic merging disabled during saves to prevent deadlocks

### New Features (v2.1):
- [x] Bulk weather backfill fetches data for all past entries
- [x] Progress tracking updates in real-time during backfill
- [x] Manual location override allows custom coordinates
- [x] Weather location editor validates coordinates
- [x] Detail view shows weather data with edit button
- [x] Menu provides multiple fetch options (current/custom location)
- [x] Custom location fetch updates weather data correctly
- [x] Backfill respects API rate limits (0.5s delay)
- [x] Settings shows count of entries without weather data

## Files Modified/Created

### New Files:
1. `Shared/Services/WeatherService.swift`
2. `Shared/Services/LocationManager.swift`
3. `NALI Migraine Log/Views/WeatherCorrelationView.swift`
4. `NALI Migraine Log/Views/WeatherLocationEditorView.swift` (v2.1)
5. `WEATHER_FEATURE_GUIDE.md` (this file)

### Modified Files:
1. `Shared/Models/MigraineEvent+CoreDataProperties.swift` - Added weather attributes
2. `NALI Migraine Log/ViewModels/MigraineViewModel.swift` - Added weather fetching, bulk backfill, custom location
3. `NALI Migraine Log/Views/MigraineRowView.swift` - Added weather display
4. `NALI Migraine Log/Views/MigraineDetailView.swift` - Enhanced weather section with edit capability (v2.1)
5. `NALI Migraine Log/Views/StatisticsView.swift` - Added weather correlation button
6. `NALI Migraine Log/Views/DisclaimerView.swift` - Added location services toggle
7. `NALI Migraine Log/Views/SettingsView.swift` - Added weather tracking and backfill sections (v2.1)
8. `NALI Migraine Log/Info.plist` - Added location permissions
9. `NALI Migraine Log/NALI_Migraine_LogApp.swift` - Added LocationManager initialization

### Core Data Changes:
**✅ COMPLETED**: The Core Data model has been updated with all weather attributes:
1. ✅ `hasWeatherData` (Boolean, default NO)
2. ✅ `weatherTemperature` (Double, default 0)
3. ✅ `weatherPressure` (Double, default 0)
4. ✅ `weatherPressureChange24h` (Double, default 0)
5. ✅ `weatherCondition` (String, optional)
6. ✅ `weatherIcon` (String, optional)
7. ✅ `weatherPrecipitation` (Double, default 0)
8. ✅ `weatherCloudCover` (Integer 16, default 0)
9. ✅ `weatherCode` (Integer 16, default 0)
10. ✅ `weatherLatitude` (Double, default 0)
11. ✅ `weatherLongitude` (Double, default 0)

**Note**: After updating the model, you must:
- Clean Build Folder (⌘⇧K)
- Reset simulator or delete app data on device
- This ensures the new schema is applied

## Conclusion

This weather correlation feature provides valuable insights into how weather patterns affect your migraines. The barometric pressure change calculation is particularly important, as rapid pressure changes are a well-documented migraine trigger. The automatic data collection and comprehensive analytics make it easy to identify patterns and share findings with healthcare providers.

The implementation is robust, privacy-focused, and completely free to use. No API keys, no registration, no costs.

---

**Questions or Issues?**
Check the console logs for detailed debugging information. All weather-related operations include emoji-prefixed logs for easy identification:
- 📍 Location updates
- 🌤️ Weather data fetched
- ✅ Success messages
- ⚠️ Warnings
- ❌ Errors

