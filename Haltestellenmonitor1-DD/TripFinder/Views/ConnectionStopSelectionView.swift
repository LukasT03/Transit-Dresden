//
//  ConnectionStopSelectionView.swift
//  Haltestellenmonitor1-DD
//
//  Created by Peter Lohse on 19.04.23.
//

import SwiftUI
import CoreLocation
import Contacts
import MapKit

struct ConnectionStopSelectionView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var favoriteStops: FavoriteStop
    @EnvironmentObject var filter: ConnectionFilter
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var location: CLLocation?
    @State private var addressString = ""
    @State private var showPicker = false

    @State private var showNoAddressAlert = false
    @State private var contactName = ""
    @State private var addresses: [CNLabeledValue<CNPostalAddress>] = []
    
    @State private var isSearchFieldFocused: Bool = true
    
    var body: some View {
        NavigationStack {
            viewBody()
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchFieldFocused,
                    placement: .navigationBarDrawer(displayMode: .always)
                )
        }  .dynamicTypeSize(.medium ... .large)
            .task(id: searchText) {
                changePlace()
            }
            .alert(
                "Bei diesem Kontakt ist keine Adresse hinterlegt.",
                isPresented: $showNoAddressAlert
            ) {
                Button {
                    // do nothing
                } label: {
                    Text("OK")
                }
            }
            .sheet(isPresented: $showPicker) {
                ContactPicker { result in
                    switch result {
                    case .selectedContact(let contact):
                        selectContact(contact: contact)
                    case .cancelled:
                        // Handle cancellation
                        break
                    }
                }
                .dynamicTypeSize(.medium ... .large)
            }
    }
    func viewBody() -> some View {
        return  Form {
            Section {
                if addressString != "" {
                    HStack {
                        Text("🏘️ \(addressString)")
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if filter.start {
                            filter.startStop = ConnectionStop(
                                displayName: addressString,
                                location: StopCoordinate(
                                    latitude: location?.coordinate.latitude ?? 0,
                                    longitude: location?.coordinate.longitude ?? 0
                                )
                            )
                        } else {
                            filter.endStop = ConnectionStop(
                                displayName: addressString,
                                location: StopCoordinate(
                                    latitude: location?.coordinate.latitude ?? 0,
                                    longitude: location?.coordinate.longitude ?? 0
                                )
                            )
                        }
                        dismiss()
                    }
                }
                HStack {
                    if contactName != "" {
                        Text("📒 \(contactName)")
                            .lineLimit(1)
                    } else {
                        Text("📒 Kontakt auswählen")
                            .foregroundColor(Color.gray)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showPicker.toggle()
                }
            }
            if addresses.count > 0 {
                Section(header: Text("Kontakt-Adressen")) {
                    List(addresses, id: \.self) { labeledAddress in
                        HStack {
                            Text(
                                "\(labeledAddress.value.street), \(labeledAddress.value.postalCode) \(labeledAddress.value.city)"
                            )
                            .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectContactAddress(address: labeledAddress.value)
                        }
                    }
                }
            }
            Section(header: Text("Haltestellen")) {
                List(searchResults, id: \.self) { stop in
                    StopRow(stop: stop)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if filter.start {
                                filter.startStop = ConnectionStop(
                                    displayName: stop.getFullName(),
                                    stop: stop
                                )
                            } else {
                                filter.endStop = ConnectionStop(
                                    displayName: stop.getFullName(),
                                    stop: stop
                                )
                            }
                            dismiss()
                        }
                }
            }
        }
        .navigationTitle(filter.start ? "🏠 Startpunkt" : "🏠 Zielpunkt")
        .toolbar {
            ToolbarItem(placement: ToolbarItemPlacement.cancellationAction) {
                Button("Schließen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: ToolbarItemPlacement.confirmationAction) {
                Button {
                    locationManager.requestCurrentLocation()
                } label: {
                    Label("", systemImage: "location")
                }
            }
        }
    }
  

    var searchResults: [Stop] {
        stops = stops.sorted {
            $0.distance ?? 0 < $1.distance ?? 0
        }

        var newStops: [Stop] = []
        stops.forEach { stop in
            if favoriteStops.isFavorite(stopID: stop.stopID) {
                newStops.append(stop)
            }
        }
        stops.forEach { stop in
            if !favoriteStops.isFavorite(stopID: stop.stopID) {
                newStops.append(stop)
            }
        }
        stops = newStops

        if searchText.isEmpty {
            return stops
        } else {
            return stops
                .filter {
                    $0.name.lowercased().contains(searchText.lowercased())
                }
        }
    }

    func selectContactAddress(address: CNPostalAddress) {
        let addressStr = "\(address.street), \(address.postalCode) \(address.city)"

        guard let request = MKGeocodingRequest(addressString: addressStr) else { return }
        Task {
            guard let location = (try? await request.mapItems)?.first?.location else {
                return
            }

            if filter.start {
                filter.startStop = ConnectionStop(
                    displayName: contactName,
                    location: StopCoordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                )
            } else {
                filter.endStop = ConnectionStop(
                    displayName: contactName,
                    location: StopCoordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                )

                if filter.startStop == nil {
                    locationManager.requestCurrentLocationComplete {
                        locationManager.lookUpCurrentLocation { mapItem in
                            if let mapItem {
                                filter.startStop = ConnectionStop(
                                    displayName: mapItem.singleLineAddress,
                                    location: StopCoordinate(
                                        latitude: locationManager.location?.latitude ?? 0,
                                        longitude: locationManager.location?.longitude ?? 0
                                    )
                                )
                            }
                        }
                    }
                }
            }
            dismiss()
        }
    }

    func changePlace() {
        guard let request = MKGeocodingRequest(addressString: searchText) else { return }
        Task {
            guard let mapItem = (try? await request.mapItems)?.first else {
                return
            }

            self.location = mapItem.location
            addressString = mapItem.singleLineAddress
        }
    }

    func selectContact(contact: CNContact) {
        if contact.givenName == "" && contact.familyName == "" && contact.organizationName != "" {
            contactName = contact.organizationName
        } else {
            contactName = "\(contact.givenName) \(contact.familyName)"
        }

        if contact.postalAddresses.count <= 0 {
            addresses = []
            showNoAddressAlert.toggle()
            return
        }

        if contact.postalAddresses.count == 1 {
            selectContactAddress(address: contact.postalAddresses.first!.value)
            return
        }

        addresses = contact.postalAddresses
    }
}

struct ConnectionStopSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionStopSelectionView()
            .environmentObject(LocationManager())
            .environmentObject(FavoriteStop())
            .environmentObject(ConnectionFilter())
    }
}
