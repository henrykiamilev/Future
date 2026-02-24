import Foundation
import CoreLocation
import MapKit
import Combine

// ============================================================================
// LOCATION SERVICE — GPS Auto-Detect + Autocomplete Search
// ============================================================================
// Provides:
//   1. Single-shot GPS → reverse geocode → "City, State" string
//   2. MKLocalSearchCompleter for typeahead location autocomplete
// ============================================================================

protocol LocationServiceProtocol: AnyObject {
    var searchResults: [MKLocalSearchCompletion] { get }
    var isDetecting: Bool { get }
    var detectedLocation: String? { get }

    func requestCurrentLocation() async throws -> String
    func updateSearch(query: String)
    func resolveCompletion(_ completion: MKLocalSearchCompletion) async -> String
}

@MainActor
final class LocationService: NSObject, ObservableObject, LocationServiceProtocol {

    // MARK: - Published State

    @Published private(set) var searchResults: [MKLocalSearchCompletion] = []
    @Published private(set) var isDetecting = false
    @Published private(set) var detectedLocation: String?

    // MARK: - Internals

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let completer = MKLocalSearchCompleter()

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        completer.delegate = self
        completer.resultTypes = .address
    }

    // MARK: - GPS Detection

    /// Requests a single GPS fix, reverse geocodes it, and returns a "City, State" string.
    func requestCurrentLocation() async throws -> String {
        isDetecting = true
        defer { isDetecting = false }

        // Request permission if needed
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Wait briefly for the authorization callback
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let currentStatus = locationManager.authorizationStatus
        guard currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }

        // Get single location fix
        let location = try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<CLLocation, Error>) in
            self?.locationContinuation = continuation
            self?.locationManager.requestLocation()
        }

        // Reverse geocode
        let placemarks = try await geocoder.reverseGeocodeLocation(location)

        guard let placemark = placemarks.first else {
            throw LocationError.geocodeFailed
        }

        let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
        let state = placemark.administrativeArea ?? ""
        let result: String
        if !city.isEmpty && !state.isEmpty {
            result = "\(city), \(state)"
        } else if !city.isEmpty {
            result = city
        } else if !state.isEmpty {
            result = state
        } else {
            throw LocationError.geocodeFailed
        }

        detectedLocation = result
        return result
    }

    // MARK: - Autocomplete Search

    func updateSearch(query: String) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            searchResults = []
            completer.cancel()
        } else {
            completer.queryFragment = query
        }
    }

    /// Resolves a completion into a clean location string (e.g. "Los Angeles, CA")
    func resolveCompletion(_ completion: MKLocalSearchCompletion) async -> String {
        // MKLocalSearchCompletion provides title + subtitle
        let title = completion.title
        let subtitle = completion.subtitle
        if subtitle.isEmpty {
            return title
        }
        return "\(title), \(subtitle)"
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationService: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            searchResults = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            searchResults = []
        }
    }
}

// MARK: - Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case geocodeFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access is needed to auto-detect your location. You can enable it in Settings."
        case .geocodeFailed:
            return "Could not determine your location name. Try entering it manually."
        }
    }
}
