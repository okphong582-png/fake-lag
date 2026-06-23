import Foundation

/// LagURLProtocol intercepts all URL requests and adds artificial delay
/// when lag is enabled. This simulates light network congestion.
class LagURLProtocol: URLProtocol {

    // MARK: - Shared state
    static var isLagEnabled: Bool = false
    static var lagDelaySeconds: Double = 0.8  // Delay per request (seconds)

    private var dataTask: URLSessionDataTask?
    private static var session: URLSession = {
        let config = URLSessionConfiguration.default
        // Prevent recursive interception
        config.protocolClasses = [URLProtocol.self]
        return URLSession(configuration: config)
    }()

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        // Only intercept http/https when lag is active
        guard isLagEnabled,
              let scheme = request.url?.scheme,
              (scheme == "http" || scheme == "https") else { return false }
        // Prevent infinite recursion
        if URLProtocol.property(forKey: "LagHandled", in: request) != nil {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let delay = LagURLProtocol.lagDelaySeconds
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            let mutableRequest = (self.request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(true, forKey: "LagHandled", in: mutableRequest)

            let task = LagURLProtocol.session.dataTask(with: mutableRequest as URLRequest) { data, response, error in
                if let error = error {
                    self.client?.urlProtocol(self, didFailWithError: error)
                    return
                }
                if let response = response {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
            task.resume()
            self.dataTask = task
        }
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }
}
