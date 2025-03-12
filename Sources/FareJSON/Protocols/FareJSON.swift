//
//  FareJSON.swift
//
//
//  Created by Oleg on 12.03.2025.
//

import Foundation

/// A protocol representing a JSON resource that can be listed, cached, and decoded.
/// Conforming types are expected to be enums providing cases for all possible JSON files.
public protocol FareJSON: CaseIterable, Hashable {
    /// The folder path where the JSON files for this type are stored.
    static var folderPath: String { get }
    
    /// The file name associated with the JSON resource.
    var fileName: String { get }
}
