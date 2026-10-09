//
//  AddressSearch.swift
//  Transit Dresden
//

import Foundation
import MapKit
import Observation

/// Adressvorschläge während der Eingabe, auf die Region Dresden ausgerichtet
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.050446, longitude: 13.737954),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
    }

    func update(query: String) {
        if query.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(5))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Wandelt einen Vorschlag in ein Ziel mit Koordinate um
    func resolve(_ completion: MKLocalSearchCompletion) async -> ConnectionStop? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let mapItem = try? await search.start().mapItems.first else { return nil }
        let coordinate = mapItem.location.coordinate
        return ConnectionStop(
            displayName: completion.title,
            location: StopCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }
}
