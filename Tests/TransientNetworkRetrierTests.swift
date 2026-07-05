import Testing
import Foundation
import Alamofire
@testable import APSignedAPIClient

@Suite("Transient Network Retrier Tests")
struct TransientNetworkRetrierTests {

    // MARK: - Transient network errors

    @Test("Retries transient URL errors regardless of method")
    func retriesTransientURLErrors() {
        let retrier = TransientNetworkRetrier()
        #expect(retrier.shouldRetry(error: URLError(.timedOut), statusCode: nil, method: .get))
        #expect(retrier.shouldRetry(error: URLError(.dnsLookupFailed), statusCode: nil, method: .get))
        #expect(retrier.shouldRetry(error: URLError(.notConnectedToInternet), statusCode: nil, method: .post))
        #expect(retrier.shouldRetry(error: URLError(.cannotFindHost), statusCode: nil, method: .post))
        #expect(retrier.shouldRetry(error: URLError(.networkConnectionLost), statusCode: nil, method: .post))
    }

    @Test("Does not retry non-transient URL errors")
    func doesNotRetryOtherURLErrors() {
        let retrier = TransientNetworkRetrier()
        #expect(!retrier.shouldRetry(error: URLError(.badURL), statusCode: nil, method: .get))
        #expect(!retrier.shouldRetry(error: URLError(.cancelled), statusCode: nil, method: .get))
    }

    @Test("Retries transient URLError wrapped in AFError.sessionTaskFailed")
    func retriesWrappedURLError() {
        let retrier = TransientNetworkRetrier()
        let error = AFError.sessionTaskFailed(error: URLError(.timedOut))
        #expect(retrier.shouldRetry(error: error, statusCode: nil, method: .get))
    }

    @Test("Retries POSIX error 53 (software caused connection abort)")
    func retriesPOSIXConnectionAbort() {
        let retrier = TransientNetworkRetrier()
        let error = NSError(domain: NSPOSIXErrorDomain, code: 53)
        #expect(retrier.shouldRetry(error: error, statusCode: nil, method: .post))
    }

    // MARK: - HTTP status codes

    @Test("Retries retryable 5xx responses for idempotent methods")
    func retries5xxForIdempotentMethods() {
        let retrier = TransientNetworkRetrier()
        for status in [500, 501, 502, 503, 504] {
            #expect(retrier.shouldRetry(error: nil, statusCode: status, method: .get))
        }
        #expect(retrier.shouldRetry(error: nil, statusCode: 503, method: .head))
        #expect(retrier.shouldRetry(error: nil, statusCode: 503, method: .put))
        #expect(retrier.shouldRetry(error: nil, statusCode: 503, method: .delete))
    }

    @Test("Does not retry 5xx for non-idempotent methods")
    func doesNotRetry5xxForNonIdempotentMethods() {
        let retrier = TransientNetworkRetrier()
        for status in [500, 501, 502, 503, 504] {
            #expect(!retrier.shouldRetry(error: nil, statusCode: status, method: .post))
        }
        #expect(!retrier.shouldRetry(error: nil, statusCode: 503, method: .patch))
        // Unknown method (no URLRequest available) is treated as non-idempotent.
        #expect(!retrier.shouldRetry(error: nil, statusCode: 503, method: nil))
    }

    @Test("Does not retry terminal API statuses like 404 and 410")
    func doesNotRetryTerminalStatuses() {
        let retrier = TransientNetworkRetrier()
        // 410 means session expired and 404 maps to a server error in this API;
        // neither can succeed on a second attempt.
        #expect(!retrier.shouldRetry(error: nil, statusCode: 404, method: .get))
        #expect(!retrier.shouldRetry(error: nil, statusCode: 410, method: .get))
    }

    @Test("Does not retry other client errors")
    func doesNotRetryClientErrors() {
        let retrier = TransientNetworkRetrier()
        for status in [400, 401, 403, 422, 429] {
            #expect(!retrier.shouldRetry(error: nil, statusCode: status, method: .get))
        }
    }

    // MARK: - Cancellation

    @Test("Does not retry after cancellation")
    func doesNotRetryWhenCancelled() {
        let retrier = TransientNetworkRetrier()
        retrier.isReloadingCancelled = true
        #expect(!retrier.shouldRetry(error: URLError(.timedOut), statusCode: nil, method: .get))
        #expect(!retrier.shouldRetry(error: nil, statusCode: 503, method: .get))
    }
}
