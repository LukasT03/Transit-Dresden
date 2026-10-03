//
//  MapView.swift
//  TransitDresden
//
//  Created by Peter Lohse on 21.04.23.
//

import SwiftUI
import MapKit
import CoreLocation

struct ClusterAnnonation: Identifiable {
    let id = UUID()
    var coordinates: CLLocationCoordinate2D
    var count: Int
}

struct MapView: View {
    @State var visibleStops: [Stop] = []
    @State var clusteredStops: [ClusterAnnonation] = []

    @State private var mapPosition: MapCameraPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.050446, longitude: 13.737954),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    ))

    func updateStops(_ region: MKCoordinateRegion) {
        visibleStops = stops.filter { isCoordinateInRegion($0.coordinates, region: region) }

        // Apply Clustering
        if region.span.latitudeDelta >=  2.472 { // 6
            applyCluster(visibleStops, 100*100)
        } else if region.span.latitudeDelta >=  0.893 { // 5
            applyCluster(visibleStops, 100*60)
        } else if region.span.latitudeDelta >=  0.456 { // 4
            applyCluster(visibleStops, 100*35)
        } else  if region.span.latitudeDelta >=  0.156 { // 3
            applyCluster(visibleStops, 100*15)
        } else if region.span.latitudeDelta >=  0.084 { // 2
            applyCluster(visibleStops, 100*8)
        } else if region.span.latitudeDelta >= 0.0707 { // 1
            applyCluster(visibleStops, 100*3)
        } else if region.span.latitudeDelta < 0.084 { // none
            clusteredStops = []
        }
    }

    func applyCluster(_ data: [Stop], _ stepSize: CLLocationDistance) {
        var coordinatesMapping: [String: CLLocationCoordinate2D] = [:]
        var stopClusterMap: [String: Int] = [:]

        data.forEach { element in
            let elementKey = coordinatesToKey(element.coordinates)
            if stopClusterMap.isEmpty {
                coordinatesMapping[elementKey] = element.coordinates
                stopClusterMap[elementKey] = 1
                return
            }

            let currentPin = CLLocation(latitude: element.coordinates.latitude, longitude: element.coordinates.longitude)
            var isAlreadyClustered = false

            stopClusterMap.forEach { existingClusterPin in
                let loc = coordinatesMapping[existingClusterPin.key]!
                let existingAnnotation = CLLocation(latitude: loc.latitude, longitude: loc.longitude)

                if existingAnnotation.distance(from: currentPin) <= stepSize {
                    stopClusterMap[existingClusterPin.key] = (stopClusterMap[existingClusterPin.key] ?? 1) + 1
                    isAlreadyClustered = true
                    return
                }
            }
            if isAlreadyClustered { return }
            // add new element
            coordinatesMapping[elementKey] = element.coordinates
            stopClusterMap[elementKey] = 1
        }
        clusteredStops = stopClusterMap.map({ (key, value) in
            ClusterAnnonation(coordinates: coordinatesMapping[key]!, count: value)
        })
    }

    func coordinatesToKey(_ coords: CLLocationCoordinate2D) -> String {
        return "\(coords.latitude)x\(coords.longitude)"
    }

    var body: some View {
        Map(position: $mapPosition) {
            if clusteredStops.isEmpty {
                ForEach(visibleStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinates) {
                        NavigationLink(value: stop) {
                            Image(systemName: "h.circle.fill")
                                .foregroundColor(Color("MapColor"))
                                .background(Circle().fill(Color(.systemBackground)) .shadow(radius: 1))
                        }
                    }
                }
            } else {
                ForEach(clusteredStops) { clusterStop in
                    Annotation(coordinate: clusterStop.coordinates) {
                        Image(systemName: "h.circle.fill")
                            .foregroundColor(Color("MapColor"))
                            .background(Circle().fill(Color(.systemBackground)) .shadow(radius: 1))
                    } label: {
                        Text("\(clusterStop.count)")
                    }
                }
            }
        }
        .onMapCameraChange { mapCameraUpdateContext in
            updateStops(mapCameraUpdateContext.region)
        }
        .mapStyle(.standard)
        .mapControls {
            MapScaleView()
            MapUserLocationButton()
            MapCompass()
        }
        .navigationTitle("Karte")
        .navigationBarTitleDisplayMode(.inline)
    }

    func isCoordinateInRegion(_ coordinate: CLLocationCoordinate2D, region: MKCoordinateRegion) -> Bool {
        let latMin = region.center.latitude - (region.span.latitudeDelta / 2)
        let latMax = region.center.latitude + (region.span.latitudeDelta / 2)
        let lonMin = region.center.longitude - (region.span.longitudeDelta / 2)
        let lonMax = region.center.longitude + (region.span.longitudeDelta / 2)

        return coordinate.latitude >= latMin && coordinate.latitude <= latMax &&
        coordinate.longitude >= lonMin && coordinate.longitude <= lonMax
    }
}

#Preview {
    NavigationStack {
        MapView()
    }
}
