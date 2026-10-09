//
//  Trip.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 19.04.23.
//

import Foundation

struct Trip: Hashable, Codable {
    var SessionId: String
    var Routes: [Route]
}
