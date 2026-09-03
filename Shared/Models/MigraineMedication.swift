import Foundation
import CoreData

/// Strongly-typed representation of a medication taken for a migraine.
///
/// This is a *Swift-only facade* over the existing boolean attributes on
/// `MigraineEvent` (`tookTylenol`, `tookIbuprofin`, ...).
/// On-disk storage and CloudKit schema are unchanged — every read/write still
/// goes through the same booleans, so existing data and sync paths are
/// completely unaffected.
///
/// Case order matches the order shown in the new-migraine and edit forms.
public enum MigraineMedication: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case tylenol
    case ibuprofin          // historical spelling preserved to match Core Data attribute
    case naproxen
    case excedrin
    case ubrelvy
    case nurtec
    case symbravo
    case sumatriptan
    case rizatriptan
    case eletriptan
    case naratriptan
    case frovatriptan
    case reyvow
    case trudhesa
    case elyxyb
    case other

    public var id: String { rawValue }

    /// Short brand name — used in compact UI like list rows and stat charts.
    public var displayName: String {
        switch self {
        case .tylenol:      return "Tylenol"
        case .ibuprofin:    return "Ibuprofen"
        case .naproxen:     return "Naproxen"
        case .excedrin:     return "Excedrin"
        case .ubrelvy:      return "Ubrelvy"
        case .nurtec:       return "Nurtec"
        case .symbravo:     return "Symbravo"
        case .sumatriptan:  return "Sumatriptan"
        case .rizatriptan:  return "Rizatriptan"
        case .eletriptan:   return "Eletriptan"
        case .naratriptan:  return "Naratriptan"
        case .frovatriptan: return "Frovatriptan"
        case .reyvow:       return "Reyvow"
        case .trudhesa:     return "Trudhesa"
        case .elyxyb:       return "Elyxyb"
        case .other:        return "Other"
        }
    }

    /// Generic (non-proprietary) name, capitalised for display.
    public var genericName: String {
        switch self {
        case .tylenol:      return "Acetaminophen"
        case .ibuprofin:    return "Ibuprofen"
        case .naproxen:     return "Naproxen"
        case .excedrin:     return "Acetaminophen, aspirin & caffeine"
        case .ubrelvy:      return "Ubrogepant"
        case .nurtec:       return "Rimegepant"
        case .symbravo:     return "Meloxicam & rizatriptan"
        case .sumatriptan:  return "Sumatriptan"
        case .rizatriptan:  return "Rizatriptan"
        case .eletriptan:   return "Eletriptan"
        case .naratriptan:  return "Naratriptan"
        case .frovatriptan: return "Frovatriptan"
        case .reyvow:       return "Lasmiditan"
        case .trudhesa:     return "Dihydroergotamine"
        case .elyxyb:       return "Celecoxib"
        case .other:        return "Other"
        }
    }

    /// Common brand names, most recognisable first. Empty for `.other`.
    public var brandNames: [String] {
        switch self {
        case .tylenol:      return ["Tylenol"]
        case .ibuprofin:    return ["Advil", "Motrin"]
        case .naproxen:     return ["Aleve"]
        case .excedrin:     return ["Excedrin"]
        case .ubrelvy:      return ["Ubrelvy"]
        case .nurtec:       return ["Nurtec ODT"]
        case .symbravo:     return ["Symbravo"]
        case .sumatriptan:  return ["Imitrex"]
        case .rizatriptan:  return ["Maxalt"]
        case .eletriptan:   return ["Relpax"]
        case .naratriptan:  return ["Amerge"]
        case .frovatriptan: return ["Frova"]
        case .reyvow:       return ["Reyvow"]
        case .trudhesa:     return ["Trudhesa"]
        case .elyxyb:       return ["Elyxyb"]
        case .other:        return []
        }
    }

    /// Drug class shown as secondary text in pickers.
    public var category: String {
        switch self {
        case .tylenol, .ibuprofin, .naproxen, .excedrin, .elyxyb:
            return "Over-the-counter / NSAID"
        case .sumatriptan, .rizatriptan, .eletriptan, .naratriptan, .frovatriptan, .symbravo:
            return "Triptan"
        case .ubrelvy, .nurtec:
            return "CGRP antagonist (gepant)"
        case .reyvow:
            return "Ditan"
        case .trudhesa:
            return "Ergot"
        case .other:
            return "Other"
        }
    }

    /// Consistent "Generic (Brand)" form used in entry forms and exports.
    public var fullDisplayName: String {
        let brands = brandNames.joined(separator: ", ")
        return brands.isEmpty ? genericName : "\(genericName) (\(brands))"
    }

    /// Lowercase keywords used by the search bar.
    public var searchKeywords: [String] {
        var keywords = [displayName.lowercased()]
        for token in [genericName] + brandNames {
            let lowered = token.lowercased()
            if !keywords.contains(lowered) { keywords.append(lowered) }
        }
        return keywords
    }

    /// Best-effort match from a legacy display string. Tolerates case,
    /// surrounding whitespace, the parenthesized generic-name suffix, and
    /// common misspellings.
    public init?(displayName: String) {
        let normalized = displayName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        for med in MigraineMedication.allCases {
            let short = med.displayName.lowercased()
            let full  = med.fullDisplayName.lowercased()
            let generic = med.genericName.lowercased()
            if normalized == short
                || normalized == full
                || normalized == generic
                || normalized.hasPrefix("\(short) (")
                || normalized.hasPrefix("\(generic) (") {
                self = med
                return
            }
        }
        switch normalized {
        case "ibuprofin": self = .ibuprofin   // tolerate old misspelling
        default: return nil
        }
    }
}

// MARK: - MigraineEvent facade

extension MigraineEvent {
    /// All medications currently flagged on this entry, exposed as a
    /// strongly-typed `Set`. Reads and writes are translated to/from the
    /// underlying boolean `@NSManaged` attributes — storage on disk is
    /// unchanged.
    public var medications: Set<MigraineMedication> {
        get {
            var result: Set<MigraineMedication> = []
            if tookTylenol      { result.insert(.tylenol) }
            if tookIbuprofin    { result.insert(.ibuprofin) }
            if tookNaproxen     { result.insert(.naproxen) }
            if tookExcedrin     { result.insert(.excedrin) }
            if tookUbrelvy      { result.insert(.ubrelvy) }
            if tookNurtec       { result.insert(.nurtec) }
            if tookSymbravo     { result.insert(.symbravo) }
            if tookSumatriptan  { result.insert(.sumatriptan) }
            if tookRizatriptan  { result.insert(.rizatriptan) }
            if tookEletriptan   { result.insert(.eletriptan) }
            if tookNaratriptan  { result.insert(.naratriptan) }
            if tookFrovatriptan { result.insert(.frovatriptan) }
            if tookReyvow       { result.insert(.reyvow) }
            if tookTrudhesa     { result.insert(.trudhesa) }
            if tookElyxyb       { result.insert(.elyxyb) }
            if tookOther        { result.insert(.other) }
            return result
        }
        set {
            tookTylenol      = newValue.contains(.tylenol)
            tookIbuprofin    = newValue.contains(.ibuprofin)
            tookNaproxen     = newValue.contains(.naproxen)
            tookExcedrin     = newValue.contains(.excedrin)
            tookUbrelvy      = newValue.contains(.ubrelvy)
            tookNurtec       = newValue.contains(.nurtec)
            tookSymbravo     = newValue.contains(.symbravo)
            tookSumatriptan  = newValue.contains(.sumatriptan)
            tookRizatriptan  = newValue.contains(.rizatriptan)
            tookEletriptan   = newValue.contains(.eletriptan)
            tookNaratriptan  = newValue.contains(.naratriptan)
            tookFrovatriptan = newValue.contains(.frovatriptan)
            tookReyvow       = newValue.contains(.reyvow)
            tookTrudhesa     = newValue.contains(.trudhesa)
            tookElyxyb       = newValue.contains(.elyxyb)
            tookOther        = newValue.contains(.other)
        }
    }

    /// Returns the active medications in canonical declaration order — useful
    /// for stable display in lists, CSV exports, etc.
    public var orderedMedications: [MigraineMedication] {
        let active = medications
        return MigraineMedication.allCases.filter { active.contains($0) }
    }
}
