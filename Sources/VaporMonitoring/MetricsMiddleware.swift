//
//  MetricsMiddleware.swift
//  VaporMonitoring
//
//  Created by Joe Smith on 07/15/2019.
//

import Metrics
import Vapor

/// Middleware to track in per-request metrics
///
/// Based [off the RED Method](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)
public final class MetricsMiddleware {
    /// Per default set to [.notFound] to ignore 404 errors
    let ignoreHttpStatus: [HTTPResponseStatus]
    
    public init(ignoreHttpStatus: [HTTPResponseStatus] = [.notFound]) {
        self.ignoreHttpStatus = ignoreHttpStatus
    }
}

extension MetricsMiddleware: Middleware {
    public func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        let start = Date()
        let response: Future<Response>
        do {
            response = try next.respond(to: request)
        } catch {
            response = request.eventLoop.newFailedFuture(error: error)
        }
        return response.map { response in
            if self.ignoreHttpStatus.contains(response.http.status) {
                return response
            }
            let dimensions = [
                ("method", request.http.method.string),
                ("path", request.http.url.path),
                ("status_code", "\(response.http.status.code)")]
            let duration = start.timeIntervalSinceNow / -1
            /// Now using a histogram with default buckets, optimised for seconds not nano seconds
            Metrics.Recorder(label: "http_requests", dimensions: dimensions, aggregate: true).record(duration)
            //Metrics.Timer(label: "http_requests", dimensions: dimensions).record(duration)
            return response
        }.catchMap { error in
            let dimensions = [
                ("method", request.http.method.string),
                ("path", request.http.url.path),
                ("error", error.localizedDescription)]
            Metrics.Counter(label: "http_exception", dimensions: dimensions).increment()
            throw error
        }
    }
}

extension MetricsMiddleware: ServiceType {
    public static func makeService(for container: Container) throws -> MetricsMiddleware {
        return MetricsMiddleware()
    }
}
