import Foundation
import CoreData

// Forward declaration for WeatherSnapshot
extension MigraineEvent {
    func updateWeatherData(from snapshot: WeatherSnapshot) {
        weatherTemperature = snapshot.temperature
        weatherPressure = snapshot.pressure
        weatherPressureChange24h = snapshot.pressureChange24h
        weatherCondition = snapshot.weatherCondition
        weatherIcon = snapshot.weatherIcon
        weatherPrecipitation = snapshot.precipitation
        weatherCloudCover = Int16(snapshot.cloudCover)
        weatherCode = Int16(snapshot.weatherCode)
        hasWeatherData = true
    }
}

extension MigraineEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MigraineEvent> {
        return NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var painLevel: Int16
    @NSManaged public var location: String?
    @NSManaged public var notes: String?
    
    // Boolean symptoms
    @NSManaged public var hasAura: Bool
    @NSManaged public var hasPhotophobia: Bool
    @NSManaged public var hasPhonophobia: Bool
    @NSManaged public var hasNausea: Bool
    @NSManaged public var hasVomiting: Bool
    @NSManaged public var hasWakeUpHeadache: Bool
    @NSManaged public var hasTinnitus: Bool
    @NSManaged public var hasVertigo: Bool
    @NSManaged public var missedWork: Bool
    @NSManaged public var missedSchool: Bool
    @NSManaged public var missedEvents: Bool
    
    // Trigger booleans
    @NSManaged public var isTriggerStress: Bool
    @NSManaged public var isTriggerLackOfSleep: Bool
    @NSManaged public var isTriggerDehydration: Bool
    @NSManaged public var isTriggerWeather: Bool
    @NSManaged public var isTriggerHormones: Bool
    @NSManaged public var isTriggerAlcohol: Bool
    @NSManaged public var isTriggerCaffeine: Bool
    @NSManaged public var isTriggerFood: Bool
    @NSManaged public var isTriggerExercise: Bool
    @NSManaged public var isTriggerScreenTime: Bool
    @NSManaged public var isTriggerOther: Bool
    
    // Medication booleans
    @NSManaged public var tookIbuprofin: Bool
    @NSManaged public var tookExcedrin: Bool
    @NSManaged public var tookTylenol: Bool
    @NSManaged public var tookSumatriptan: Bool
    @NSManaged public var tookRizatriptan: Bool
    @NSManaged public var tookNaproxen: Bool
    @NSManaged public var tookFrovatriptan: Bool
    @NSManaged public var tookNaratriptan: Bool
    @NSManaged public var tookNurtec: Bool
    @NSManaged public var tookSymbravo: Bool
    @NSManaged public var tookUbrelvy: Bool
    @NSManaged public var tookReyvow: Bool
    @NSManaged public var tookTrudhesa: Bool
    @NSManaged public var tookElyxyb: Bool
    @NSManaged public var tookOther: Bool
    @NSManaged public var tookEletriptan: Bool
    
    // String arrays for reference
    @NSManaged public var triggerStrings: String?
    @NSManaged public var medicationStrings: String?
    
    // Weather data
    @NSManaged public var weatherTemperature: Double
    @NSManaged public var weatherPressure: Double
    @NSManaged public var weatherPressureChange24h: Double
    @NSManaged public var weatherCondition: String?
    @NSManaged public var weatherIcon: String?
    @NSManaged public var weatherPrecipitation: Double
    @NSManaged public var weatherCloudCover: Int16
    @NSManaged public var weatherCode: Int16
    @NSManaged public var weatherLatitude: Double
    @NSManaged public var weatherLongitude: Double
    @NSManaged public var hasWeatherData: Bool
    
    // Computed properties
    public var duration: TimeInterval? {
        guard let startTime = startTime else { return nil }
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(startTime)
    }
    
    var selectedTriggerNames: [String] {
        var triggers: [String] = []
        if isTriggerStress { triggers.append("Stress") }
        if isTriggerLackOfSleep { triggers.append("Lack of Sleep") }
        if isTriggerDehydration { triggers.append("Dehydration") }
        if isTriggerWeather { triggers.append("Weather") }
        if isTriggerHormones { triggers.append("Menstrual") }
        if isTriggerAlcohol { triggers.append("Alcohol") }
        if isTriggerCaffeine { triggers.append("Caffeine") }
        if isTriggerFood { triggers.append("Food") }
        if isTriggerExercise { triggers.append("Exercise") }
        if isTriggerScreenTime { triggers.append("Screen Time") }
        if isTriggerOther { triggers.append("Other") }
        return triggers
    }
    
    var selectedMedicationNames: [String] {
        var medications: [String] = []
        if tookTylenol { medications.append("Tylenol (acetaminophen)") }
        if tookIbuprofin { medications.append("Ibuprofen") }
        if tookNaproxen { medications.append("Naproxen") }
        if tookExcedrin { medications.append("Excedrin") }
        if tookUbrelvy { medications.append("Ubrelvy (ubrogepant)") }
        if tookNurtec { medications.append("Nurtec (rimegepant)") }
        if tookSymbravo { medications.append("Symbravo") }
        if tookSumatriptan { medications.append("Sumatriptan") }
        if tookRizatriptan { medications.append("Rizatriptan") }
        if tookEletriptan { medications.append("Eletriptan") }
        if tookNaratriptan { medications.append("Naratriptan") }
        if tookFrovatriptan { medications.append("Frovatriptan") }
        if tookReyvow { medications.append("Reyvow (lasmiditan)") }
        if tookTrudhesa { medications.append("Trudhesa (dihydroergotamine)") }
        if tookElyxyb { medications.append("Elyxyb") }
        if tookOther { medications.append("Other") }
        return medications
    }
    
    // Weather helper methods
    func updateWeatherLocation(latitude: Double, longitude: Double) {
        weatherLatitude = latitude
        weatherLongitude = longitude
    }
    
    var weatherSummary: String {
        guard hasWeatherData else { return "No weather data" }
        return "\(weatherCondition ?? "Unknown"), \(Int(weatherTemperature))°F"
    }
    
    var pressureChangeDescription: String {
        guard hasWeatherData else { return "N/A" }
        let change = weatherPressureChange24h
        if abs(change) < 2 {
            return "Stable"
        } else if change > 0 {
            return "Rising (+\(String(format: "%.1f", change)) hPa)"
        } else {
            return "Falling (\(String(format: "%.1f", change)) hPa)"
        }
    }
    
    func toWatchSyncDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id?.uuidString ?? UUID().uuidString,
            "startTime": startTime?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
            "painLevel": painLevel,
            "location": location ?? "",
            
            // Boolean symptoms
            "hasAura": hasAura,
            "hasPhotophobia": hasPhotophobia,
            "hasPhonophobia": hasPhonophobia,
            "hasNausea": hasNausea,
            "hasVomiting": hasVomiting,
            "hasWakeUpHeadache": hasWakeUpHeadache,
            "hasTinnitus": hasTinnitus,
            "hasVertigo": hasVertigo,
            "missedWork": missedWork,
            "missedSchool": missedSchool,
            "missedEvents": missedEvents,
            
            // Medication booleans
            "tookTylenol": tookTylenol,
            "tookIbuprofin": tookIbuprofin,
            "tookNaproxen": tookNaproxen,
            "tookExcedrin": tookExcedrin,
            "tookUbrelvy": tookUbrelvy,
            "tookNurtec": tookNurtec,
            "tookSymbravo": tookSymbravo,
            "tookSumatriptan": tookSumatriptan,
            "tookRizatriptan": tookRizatriptan,
            "tookEletriptan": tookEletriptan,
            "tookNaratriptan": tookNaratriptan,
            "tookFrovatriptan": tookFrovatriptan,
            "tookReyvow": tookReyvow,
            "tookTrudhesa": tookTrudhesa,
            "tookElyxyb": tookElyxyb,
            "tookOther": tookOther,
            
            // Trigger booleans
            "isTriggerStress": isTriggerStress,
            "isTriggerLackOfSleep": isTriggerLackOfSleep,
            "isTriggerDehydration": isTriggerDehydration,
            "isTriggerWeather": isTriggerWeather,
            "isTriggerHormones": isTriggerHormones,
            "isTriggerAlcohol": isTriggerAlcohol,
            "isTriggerCaffeine": isTriggerCaffeine,
            "isTriggerFood": isTriggerFood,
            "isTriggerExercise": isTriggerExercise,
            "isTriggerScreenTime": isTriggerScreenTime,
            "isTriggerOther": isTriggerOther
        ]
        
        if let endTime = endTime {
            dict["endTime"] = endTime.timeIntervalSince1970
        }
        if let notes = notes {
            dict["notes"] = notes
        }
        
        return dict
    }
    
    func updateFromDictionary(_ dict: [String: Any]) {
        if let idString = dict["id"] as? String {
            id = UUID(uuidString: idString)
        }
        if let startTimeInterval = dict["startTime"] as? TimeInterval {
            startTime = Date(timeIntervalSince1970: startTimeInterval)
        }
        if let endTimeInterval = dict["endTime"] as? TimeInterval {
            endTime = Date(timeIntervalSince1970: endTimeInterval)
        }
        if let painLevel = dict["painLevel"] as? Int16 {
            self.painLevel = painLevel
        }
        location = dict["location"] as? String
        notes = dict["notes"] as? String
        
        // Boolean properties
        hasAura = dict["hasAura"] as? Bool ?? false
        hasPhotophobia = dict["hasPhotophobia"] as? Bool ?? false
        hasPhonophobia = dict["hasPhonophobia"] as? Bool ?? false
        hasNausea = dict["hasNausea"] as? Bool ?? false
        hasVomiting = dict["hasVomiting"] as? Bool ?? false
        hasWakeUpHeadache = dict["hasWakeUpHeadache"] as? Bool ?? false
        hasTinnitus = dict["hasTinnitus"] as? Bool ?? false
        hasVertigo = dict["hasVertigo"] as? Bool ?? false
        missedWork = dict["missedWork"] as? Bool ?? false
        missedSchool = dict["missedSchool"] as? Bool ?? false
        missedEvents = dict["missedEvents"] as? Bool ?? false
        
        // Medication booleans
        tookTylenol = dict["tookTylenol"] as? Bool ?? false
        tookIbuprofin = dict["tookIbuprofin"] as? Bool ?? false
        tookNaproxen = dict["tookNaproxen"] as? Bool ?? false
        tookExcedrin = dict["tookExcedrin"] as? Bool ?? false
        tookUbrelvy = dict["tookUbrelvy"] as? Bool ?? false
        tookNurtec = dict["tookNurtec"] as? Bool ?? false
        tookSymbravo = dict["tookSymbravo"] as? Bool ?? false
        tookSumatriptan = dict["tookSumatriptan"] as? Bool ?? false
        tookRizatriptan = dict["tookRizatriptan"] as? Bool ?? false
        tookEletriptan = dict["tookEletriptan"] as? Bool ?? false
        tookNaratriptan = dict["tookNaratriptan"] as? Bool ?? false
        tookFrovatriptan = dict["tookFrovatriptan"] as? Bool ?? false
        tookReyvow = dict["tookReyvow"] as? Bool ?? false
        tookTrudhesa = dict["tookTrudhesa"] as? Bool ?? false
        tookElyxyb = dict["tookElyxyb"] as? Bool ?? false
        tookOther = dict["tookOther"] as? Bool ?? false
        
        // Trigger booleans
        isTriggerStress = dict["isTriggerStress"] as? Bool ?? false
        isTriggerLackOfSleep = dict["isTriggerLackOfSleep"] as? Bool ?? false
        isTriggerDehydration = dict["isTriggerDehydration"] as? Bool ?? false
        isTriggerWeather = dict["isTriggerWeather"] as? Bool ?? false
        isTriggerHormones = dict["isTriggerHormones"] as? Bool ?? false
        isTriggerAlcohol = dict["isTriggerAlcohol"] as? Bool ?? false
        isTriggerCaffeine = dict["isTriggerCaffeine"] as? Bool ?? false
        isTriggerFood = dict["isTriggerFood"] as? Bool ?? false
        isTriggerExercise = dict["isTriggerExercise"] as? Bool ?? false
        isTriggerScreenTime = dict["isTriggerScreenTime"] as? Bool ?? false
        isTriggerOther = dict["isTriggerOther"] as? Bool ?? false
    }
    
    static func from(dictionary dict: [String: Any], in context: NSManagedObjectContext) throws -> MigraineEvent {
        let migraine = MigraineEvent(context: context)
        migraine.updateFromDictionary(dict)
        return migraine
    }
}

extension MigraineEvent: Identifiable {} 