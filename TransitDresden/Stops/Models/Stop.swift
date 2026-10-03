//
//  Stop.swift
//  TransitDresden
//
//  Created by Peter Lohse on 18.04.23.
//

import Foundation
import CoreLocation

struct Stop: Hashable, Codable, Identifiable {
    let id = UUID()

    var stopID: Int
    var gid: String
    var name: String
    var place: String
    var x: String
    var y: String


    var coordinates: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(self.y) ?? 0, longitude: Double(self.x) ?? 0)
    }

    private enum CodingKeys: String, CodingKey {
        case stopID, gid, name, place, x, y
    }

    func getFullName() -> String {
        return "\(name) \(place)"
    }

    func getName() -> String {
        return name
    }

}
