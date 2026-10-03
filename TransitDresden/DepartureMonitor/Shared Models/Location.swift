//
//  Location.swift
//  TransitDresden
//
//  Created by Tom Braune on 27.02.25.
//

struct Location: Hashable, Codable {
    var id: String?
    // var isGlobalId: Bool?
    var name: String
    var disassembledName: String?
    var type: String
    var coord: [Int]?
    var properties: Stop_Property?
    // var parent: Location?
}
