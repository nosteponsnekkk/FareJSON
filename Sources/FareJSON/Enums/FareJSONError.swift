//
//  FareJSONError.swift
//
//
//  Created by Oleg on 12.03.2025.
//

import Foundation

/// Errors that can occur when working with cached JSON data.
enum FareJSONError: Error {
    /// Indicates that no cached JSON data was found for the requested file.
    case noCachedJSON
}
