//
//  FareJSONService.swift
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
    
    /// Cached directory URL for storing downloaded JSON files.
    private lazy var documentsDirectory: URL = {
        guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FareJSON") else {
            fatalError("No documents directory found.")
        }
        // Create the directory if it does not exist.
        try? fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
        return docsURL
    }()
    
    /// URL for a metadata file that persists the revision tags.
    private lazy var metadataFileURL: URL = {
        return documentsDirectory.appendingPathComponent("FareJSONMetadata.json")
    }()
    
    /// Dictionary mapping file names to their revision tags.
    /// This is persisted to disk between sessions.
    private var metadata: [String: String] = [:]
    
    /// A dictionary for caching JSON file entries using the file name as key.
    private var cachedJSONs: [String: CachedJSONEntry] = [:]
    
    // MARK: - Initialization
    
    /// Private initializer to enforce singleton usage.
    private init() {
        loadMetadata()
    }
    
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
    
    /// Downloads a JSON file from remote storage, writes it locally, and returns the local file URL.
    ///
    /// - Parameter key: The key of the JSON file to download.
    /// - Returns: A `URL` pointing to the locally saved JSON file.
    /// - Throws: An error if the download, buffering, or file write fails.
    func loadJSON(key: String) async throws -> URL {
        // Fetch the JSON object from remote storage.
        let response = try await swiftyFare.getObject(withKey: key)
        
        // Determine the local file URL for saving.
        let localFileURL = documentsURL(for: (key as NSString).lastPathComponent)
        
        // Collect the response data up to the defined buffer limit.
        let buffer = try await response.collect(upTo: bufferLimit)
        let data = Data(buffer: buffer)
        
        // Write the downloaded data to the local file.
        try data.write(to: localFileURL)
        
        return localFileURL
    }
    
    // MARK: - Metadata Persistence
    
    /// Loads the metadata dictionary from the metadata file, if it exists.
    func loadMetadata() {
        if fileManager.fileExists(atPath: metadataFileURL.path) {
            do {
                let data = try Data(contentsOf: metadataFileURL)
                let dict = try JSONDecoder().decode([String: String].self, from: data)
                metadata = dict
            } catch {
                print("Failed to load metadata: \(error)")
            }
        }
    }
    
    /// Saves the metadata dictionary to the metadata file.
    func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataFileURL)
        } catch {
            print("Failed to save metadata: \(error)")
        }
    }
}

// MARK: - FareJSONClient Conformance

public extension FareJSONService {
    
    /// Downloads and caches all JSON files for a given `FareJSON` type.
    ///
    /// This method lists all files in the specified folder, matches them with the provided enum cases,
    /// checks the remote revision tag against the locally stored tag, downloads updated JSON files if needed,
    /// and caches them locally.
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
            guard let fileName = (object.key as NSString?)?.lastPathComponent,
                  let key = object.key,
                  let eTag = object.eTag,
                  let item = itemsByFileName[fileName] else { continue }
            
            let localFileURL = documentsURL(for: fileName)
            let fileExists = fileManager.fileExists(atPath: localFileURL.path)
       
            
            if fileExists, let localTag = metadata[fileName], localTag == eTag {
                // Cached file is up-to-date.
                cachedJSONs[fileName] = CachedJSONEntry(item: item, fileURL: localFileURL, revisionTag: localTag)
            } else {
                // Either no local file exists or the revision tag has changed – download new JSON.
                let newLocalURL = try await loadJSON(key: key)
                // Update the metadata with the new revision tag.
                metadata[fileName] = eTag
                cachedJSONs[fileName] = CachedJSONEntry(item: item, fileURL: newLocalURL, revisionTag: eTag)
            }
        }
        // Persist updated metadata.
        saveMetadata()
    }
    
    /// Retrieves and decodes a cached JSON file into a specified type.
    ///
    /// - Parameter json: The `FareJSON` enum case representing the cached JSON file.
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
        
        /// The revision tag associated with the cached JSON.
        let revisionTag: String
        
        /// Initializes a new cached JSON entry.
        ///
        /// - Parameters:
        ///   - item: The FareJSON enum case.
        ///   - fileURL: The local file URL where the JSON is stored.
        ///   - revisionTag: The revision tag for the JSON file.
        init(item: any FareJSON, fileURL: URL, revisionTag: String) {
            self.item = item
            self.fileURL = fileURL
            self.revisionTag = revisionTag
        }
    }
}
