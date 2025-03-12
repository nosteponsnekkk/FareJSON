//
//  FareJSONService.swift
//
//  Created by varbodysomeview on 12.03.2025.
//  Updated: 2025-03-12
//

import Foundation
import SwiftyFare
import SotoS3

/// A singleton service that manages downloading, caching, and decoding of JSON files.
/// Conforming to the `FareJSONClient` protocol, this service abstracts the process of fetching
/// JSON from remote S3 storage, caching it locally, and decoding it into application-specific models.
///
/// The service leverages the SwiftyFare SDK for network operations and uses the local file system
/// to persist downloaded JSON data.
public final class FareJSONService: FareJSONClient {
    
    // MARK: - Private Properties
    
    /// The default instance of SwiftyFare used for making network requests.
    private let swiftyFare = SwiftyFare.default
    
    /// The shared file manager used to perform file system operations.
    private let fileManager = FileManager.default
    
    /// Maximum allowed buffer size (in bytes) when downloading JSON data (set to 1 MB).
    private let bufferLimit: Int = 1 * 1024 * 1024
    
    /// The documents directory URL for storing downloaded JSON files.
    /// This directory is lazily initialized and created if it does not already exist.
    private lazy var documentsDirectory: URL = {
        guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FareJSON") else {
            fatalError("No documents directory found.")
        }
        // Attempt to create the directory if it doesn't exist.
        try? fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
        return docsURL
    }()
    
    /// A cache mapping file names to their corresponding cached JSON entries.
    /// This is used to avoid repeated downloads and to provide fast access to JSON data.
    private var cachedJSONs: [String: CachedJSONEntry] = [:]
    
    // MARK: - Initialization
    
    /// Private initializer to enforce singleton usage.
    private init() { }
    
    /// Shared singleton instance conforming to `FareJSONClient`.
    public static let shared: FareJSONClient = FareJSONService()
}

// MARK: - File Management and JSON Downloading

private extension FareJSONService {
    
    /// Constructs a file URL within the cached documents directory for a given file name.
    ///
    /// - Parameter fileName: The name of the file.
    /// - Returns: A `URL` representing the expected local storage location of the file.
    func documentsURL(for fileName: String) -> URL {
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    /// Downloads a JSON file from remote storage, writes it to a local file, and returns the file URL.
    ///
    /// This method performs the following steps:
    /// 1. Retrieves the JSON object using the SwiftyFare client.
    /// 2. Determines a local file URL based on the last path component of the provided key.
    /// 3. Collects the response data up to the defined buffer limit.
    /// 4. Writes the data to the local file system.
    ///
    /// - Parameter key: The key (or path) of the JSON file to download.
    /// - Returns: A `URL` pointing to the locally saved JSON file.
    /// - Throws: An error if the network download, data buffering, or file writing fails.
    func loadJSON(key: String) async throws -> URL {
        // Retrieve the JSON object from the remote storage.
        let response = try await swiftyFare.getObject(withKey: key)
        
        // Determine the local file URL based on the file name extracted from the key.
        let localFileURL = documentsURL(for: (key as NSString).lastPathComponent)
        
        // Collect the response data up to the specified buffer limit.
        let buffer = try await response.collect(upTo: bufferLimit)
        let data = Data(buffer: buffer)
        
        // Write the collected data to the local file.
        try data.write(to: localFileURL)
        
        return localFileURL
    }
}

// MARK: - FareJSONClient Conformance

public extension FareJSONService {
    
    /// Downloads and caches all JSON files corresponding to a given `FareJSON` type.
    ///
    /// This method:
    /// 1. Determines the remote folder path from the provided `FareJSON` type.
    /// 2. Retrieves a list of JSON file objects available in that folder.
    /// 3. Matches the retrieved file names with the expected enum cases defined in `FareJSON`.
    /// 4. Downloads each JSON file and caches its local file URL.
    ///
    /// - Parameter json: The type conforming to `FareJSON` that represents the expected JSON files.
    /// - Throws: An error if listing remote files, downloading, or file operations fail.
    func prepare<Item: FareJSON>(_ json: Item.Type) async throws {
        // Obtain the remote folder path associated with the FareJSON type.
        let folder = json.folderPath
        
        // Retrieve the list of file objects from remote storage within the folder.
        let objects = try await swiftyFare.listFiles(inDirectory: folder)
        
        // Build a lookup dictionary mapping file names to their corresponding FareJSON enum cases.
        var itemsByFileName = [String: Item]()
        for item in Item.allCases {
            itemsByFileName[item.fileName] = item
        }
        
        // Iterate through each retrieved object from remote storage.
        for object in objects {
            // Extract the file name from the object's key and validate its presence in the expected items.
            guard let fileName = (object.key as NSString?)?.lastPathComponent,
                  let key = object.key,
                  let item = itemsByFileName[fileName] else { continue }
            
            // Download the JSON file and get its local URL.
            let localURL = try await loadJSON(key: key)
            // Create a cache entry linking the FareJSON enum case with the downloaded file's URL.
            let entry = CachedJSONEntry(item: item, fileURL: localURL)
            
            // Store the cache entry using the file name as the key.
            cachedJSONs[fileName] = entry
        }
    }
    
    /// Retrieves and decodes a cached JSON file into an instance of the specified type.
    ///
    /// This method checks if the JSON file corresponding to the provided `FareJSON` enum case
    /// has been cached. If so, it reads the local file, decodes its contents into the desired type,
    /// and returns the decoded object.
    ///
    /// - Parameters:
    ///   - json: The `FareJSON` enum case representing the cached JSON file.
    /// - Returns: A decoded object of type `T`.
    /// - Throws: `FareJSONError.noCachedJSON` if the JSON file is not found in the cache,
    ///           or a decoding error if the file's contents cannot be parsed into the expected type.
    func getJSON<Item: FareJSON, T: Decodable>(json: Item) throws -> T {
        // Look up the cached JSON entry using the file name from the FareJSON enum case.
        guard let entry = cachedJSONs[json.fileName] else {
            throw FareJSONError.noCachedJSON
        }
        // Read the data from the locally cached file.
        let data = try Data(contentsOf: entry.fileURL)
        // Decode and return the data as the specified type.
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Private Cached JSON Entry

/// Private extension containing the structure used for caching JSON files.
private extension FareJSONService {
    /// Represents a cached JSON file entry.
    struct CachedJSONEntry {
        /// The FareJSON enum case associated with this JSON file.
        let item: any FareJSON
        
        /// The local file URL where the JSON file is stored.
        var fileURL: URL
        
        /// Creates a new cached JSON entry.
        ///
        /// - Parameters:
        ///   - item: The FareJSON enum case representing the file.
        ///   - fileURL: The local file URL where the JSON data is saved.
        init(item: any FareJSON, fileURL: URL) {
            self.item = item
            self.fileURL = fileURL
        }
    }
}
