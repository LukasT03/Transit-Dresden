//
//  Route.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 19.04.23.
//

import Foundation

struct Route: Hashable, Codable {
    var Interchanges: Int
    var PartialRoutes: [PartialRoute]
}
