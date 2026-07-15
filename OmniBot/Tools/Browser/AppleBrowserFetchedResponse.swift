import Foundation

nonisolated struct AppleBrowserFetchedResponse: Sendable {
    let requestedURL: String
    let finalURL: String
    let statusCode: Int
    let isSuccessfulHTTPResponse: Bool
    let wasRedirected: Bool
    let contentType: String?
    let contentDisposition: String?
    let data: Data
}
