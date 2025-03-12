//
//  FareJSONService.swift
//
//
//  Created by Oleg on 12.03.2025.
//  Refactored and optimized by [Your Name]
//

import Foundation
import SwiftyFare
import SotoS3

/// A singleton service that manages downloading, caching, and decoding of JSON files.
/// It conforms to the `FareJSONClient` protocol.
public final class FareJSONService: FareJSONClient {
    
    // MARK: - Private Properties
    
    /// Default instance of SwiftyFare used for network operations.
    private let swiftyFare = SwiftyFare.default
    
    /// Default file manager used to handle file operations.
    private let fileManager = FileManager.default
    
    /// Maximum allowed buffer size when downloading JSON data (1 MB).
    private let bufferLimit: Int = 1 * 1024 * 1024
    
    /// A cached directory URL for storing downloaded JSON files.
    private lazy var documentsDirectory: URL = {
        guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FareJSON") else {
            fatalError("No documents directory found.")
        }
        // Create the directory if it does not exist.
        try? fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
        return docsURL
    }()
    
    /// A dictionary for caching JSON file entries using the file name as key.
    private var cachedJSONs: [String: CachedJSONEntry] = [:]
    
    // MARK: - Initialization
    
    /// Private initializer to enforce singleton usage.
    private init() { }
    
    /// Shared singleton instance conforming to `FareJSONClient`.
    public static let shared: FareJSONClient = FareJSONService()
}

// MARK: - File Management and JSON Downloading

private extension FareJSONService {
    
    /// Returns the file URL within the cached documents directory for a given file name.
    ///
    /// - Parameter fileName: The name of the file.
    /// - Returns: A `URL` pointing to the expected location of the file.
    func documentsURL(for fileName: String) -> URL {
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    /// Downloads a JSON file from the remote storage, writes it locally, and returns the local file URL.
    ///
    /// - Parameter fileName: The name of the JSON file to download.
    /// - Returns: A `URL` pointing to the locally saved JSON file.
    /// - Throws: An error if the download, buffering, or file write fails.
    func loadJSON(fileName: String) async throws -> URL {
        // Fetch the JSON object from remote storage.
        let response = try await swiftyFare.getObject(withKey: fileName)
        
        // Determine the local file URL for saving.
        let localFileURL = documentsURL(for: fileName)
        
        // Collect the response data up to the defined buffer limit.
        let buffer = try await response.collect(upTo: bufferLimit)
        let data = Data(buffer: buffer)
        
        // Write the downloaded data to the local file.
        try data.write(to: localFileURL)
        
        return localFileURL
    }
}

// MARK: - FareJSONClient Conformance

public extension FareJSONService {
    
    /// Downloads and caches all JSON files for a given `FareJSON` type.
    ///
    /// The method lists all files in the specified folder, matches them with the provided enum cases,
    /// downloads the JSON files, and caches them locally.
    ///
    /// - Parameter json: The type conforming to `FareJSON` that represents the JSON files.
    /// - Throws: An error if listing, downloading, or file operations fail.
    func prepare<Item: FareJSON>(_ json: Item.Type) async throws {
        // Determine the folder path from the FareJSON type.
        let folder = json.folderPath
        
        // Retrieve the list of file objects available in the remote storage.
        let objects = try await swiftyFare.listFiles(inDirectory: folder)
        
        // Map each enum case to its file name for easy lookup.
        var itemsByFileName = [String: Item]()
        for item in Item.allCases {
            itemsByFileName[item.fileName] = item
        }
        
        // Process each object retrieved from remote storage.
        for object in objects {
            // Check if the object's key matches one of the expected file names.
            guard let fileName = object.key,
                  let item = itemsByFileName[fileName] else { continue }
            
            // Download and store the JSON locally.
            let localURL = try await loadJSON(fileName: fileName)
            let entry = CachedJSONEntry(item: item, fileURL: localURL)
            
            // Cache the entry for future retrieval.
            cachedJSONs[fileName] = entry
        }
    }
    
    /// Retrieves and decodes a cached JSON file into a specified type.
    ///
    /// - Parameters:
    ///   - json: The `FareJSON` enum case representing the cached JSON file.
    /// - Returns: A decoded object of type `T`.
    /// - Throws: `FareJSONError.noCachedJSON` if the file is not found in the cache, or
    ///           decoding errors if the file contents cannot be parsed into the expected type.
    func getJSON<Item: FareJSON, T: Decodable>(json: Item) throws -> T {
        // Retrieve the cached entry for the specified JSON file.
        guard let entry = cachedJSONs[json.fileName] else {
            throw FareJSONError.noCachedJSON
        }
        // Load data from the cached file.
        let data = try Data(contentsOf: entry.fileURL)
        // Decode and return the JSON data into the expected type.
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Private Cached JSON Entry

/// A structure representing a cached JSON file entry.
private extension FareJSONService {
    struct CachedJSONEntry {
        /// The FareJSON enum case associated with the JSON file.
        let item: any FareJSON
        
        /// The local file URL where the JSON file is stored.
        var fileURL: URL
        
        /// Initializes a new cached JSON entry.
        ///
        /// - Parameters:
        ///   - item: The FareJSON enum case.
        ///   - fileURL: The local file URL where the JSON is stored.
        init(item: any FareJSON, fileURL: URL) {
            self.item = item
            self.fileURL = fileURL
        }
    }
}
