//
//  LocationManager.swift
//  TransitDresden
//
//  Created by Peter Lohse on 18.04.23.
//

import Foundation
import CoreLocation
import MapKit
import SwiftUI

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    var _region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.050446, longitude: 13.737954),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var region: Binding<MKCoordinateRegion> {
        Binding(
            get: { self._region },
            set: { self._region = $0 }
        )
    }

    @Published var location: CLLocationCoordinate2D?
    @Published var llocation: CLLocation?

    private var completion: (() -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() {
        locationManager.startUpdatingLocation()
    }

    func requestCurrentLocationComplete(completion: @escaping () -> Void) {
        self.completion = completion
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.requestCurrentLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }

        var newStops: [Stop] = []
        stops.forEach { stop in
            var newStop = stop
            newStop.distance = location.distance(from: CLLocation(latitude: stop.coordinates.latitude, longitude: stop.coordinates.longitude))
            newStops.append(newStop)
        }
        stops = newStops

        DispatchQueue.main.async {
            self.location = location.coordinate
            self.region.wrappedValue = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        self.llocation = location

        if completion != nil {
            completion!()
            completion = nil
        }

        locationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle any errors here...
        print("LocationManager Error: \(error)")
    }

    func lookUpCurrentLocation(completionHandler: @escaping @MainActor (MKMapItem?)
                    -> Void ) {
        // Use the last reported location.
        guard let lastLocation = self.llocation,
              let request = MKReverseGeocodingRequest(location: lastLocation) else {
            // No location was available.
            Task { @MainActor in completionHandler(nil) }
            return
        }

        // Look up the location and pass it to the completion handler
        Task { @MainActor in
            // An error during geocoding results in nil
            let mapItems = try? await request.mapItems
            completionHandler(mapItems?.first)
        }
    }
}

extension MKMapItem {
    /// Single line address without country, e.g. "Postplatz 1, 01067 Dresden"
    var singleLineAddress: String {
        addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? address?.shortAddress
            ?? name
            ?? ""
    }
}
