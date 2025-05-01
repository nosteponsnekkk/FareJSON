//
//  FareJSONClient.swift
//
//
//  Created by Oleg on 12.03.2025.
//

import Foundation

/// A protocol defining the client interface for preparing and retrieving JSON data.
public protocol FareJSONClient: AnyObject {
    
    /// Downloads and caches all JSON files for a given `FareJSON` type.
    ///
    /// - Parameter json: The type conforming to `FareJSON` that represents the JSON files.
    /// - Throws: An error if the preparation (download or caching) fails.
    func prepare<Item: FareJSON>(_ json: Item.Type) async throws
    
    /// Retrieves and decodes a cached JSON file.
    ///
    /// - Parameter json: The `FareJSON` enum case representing the cached JSON file.
    /// - Returns: A decoded object of the expected type.
    /// - Throws: An error if the JSON file is not cached or if decoding fails.
    func getJSON<Item: FareJSON, T: Decodable>(json: Item) throws -> T
    
    func getData<Item: FareJSON>(json: Item) throws -> Data 
}
