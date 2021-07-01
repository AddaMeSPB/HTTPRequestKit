import Foundation
import Combine

// Extension Start Here

extension JSONDecoder {
  public static let ISO8601JSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

// Extension Finished Here

public struct ContentType: Equatable {
  public var content: String

  public static var json: Self {
    .init(content: "application/json")
  }

  public static var urlFormEncoded: Self {
    .init(content: "application/x-www-form-urlencoded")
  }

  public static var multipartFormData: Self {
    .init(content: "multipart/form-data")
  }
}

public struct DataType {
  public var data: Data?
  public var queryItems: [URLQueryItem]?
  public var parameters: [String: Any]?

  public static var none: DataType {
    .init(data: nil)
  }

  static public func query(with items: [URLQueryItem] ) -> Self {
    return .init(queryItems: items)
  }

  static public func query(with params: [String: Any]) -> Self {
    return .init(parameters: params)
  }

  static public func encodable<T>(input: T, encoder: JSONEncoder = .init() ) -> Self where T: Encodable {

    do {
      let data = try encoder.encode(input)
      return .init(data: data)
    } catch let error {
      assertionFailure("encodable encoder error: \(error)")
      return .init(data: Data())
    }

  }

  static public func parameters<T>(input: T, encoder: JSONEncoder = .init() ) -> Self {
    do {
      let data = try JSONSerialization.data(withJSONObject: input, options: .prettyPrinted)
      return .init(data: data)
    } catch let error {
      assertionFailure("parameters encoder error: \(error)")
      return .init(data: Data())
    }
  }

}

public struct HTTPError: Error, Equatable {
  public static func == (lhs: HTTPError, rhs: HTTPError) -> Bool {
    return lhs.description == rhs.description
  }

  public var description: String
  public let reason: Error?

  public static var nonHTTPResponse: Self {
    .init(description: "Non-HTTP response received", reason: nil)
  }

  public static var missingTokenFromIOS: Self {
    .init(description: "JWT token are missing on ios app", reason: nil)
  }

  public static func requestFailed(_ statusCode: Int) -> Self {
    return .init(description: "Request Failed HTTP with error - \(statusCode)", reason: nil)
  }

  public static func serverError(_ statusCode: Int) -> Self {
    return .init(description: "Server Error - \(statusCode)", reason: nil)
  }

  public static func networkError(_ error: Error?) -> Self {
    return .init(description: "Failed to load the request: \(String(describing: error))", reason: error)
  }

  public static func authError(_ statusCode: Int) -> Self {
    return .init(description: "Authentication Token is expired: \(statusCode)", reason: nil)
  }

  public static func decodingError(_ decError: DecodingError) -> Self {
    return .init(description: "Failed to process response: \(decError)", reason: decError)
  }

  public static func unhandledResponse(_ statusCode: Int) -> Self {
    return .init(description: "Unhandled HTTP Response Status code: \(statusCode)", reason: nil)
  }

  public static func custom(_ status: String, _ error: Error?) -> Self {
    return .init(description: "\(status)", reason: error)
  }

}

public enum HTTPMethod: String {
  case get
  case post
  case put
  case patch
  case delete
}

public enum AuthType {
  case bearer(token: String)
  case basic(username: String, password: String)
  case none
}

public struct HttpRequest {
  public var baseURL: URL
  public var path: String
  public var method: HTTPMethod
  public var headers: [String: String]?
  public var authType: AuthType
  public var contentType: ContentType
  public var dataType: DataType
  let urlRequest: () -> URLRequest

  // swiftlint:disable function_parameter_count
  static func getRequest(
    _ url: URL, headers: [String: String]?, dataType: DataType,
    authType: AuthType, contentType: ContentType, method: HTTPMethod
  ) -> URLRequest {

    let url = url.queryWith(items: dataType.queryItems, params: dataType.parameters)
    var request = URLRequest(url: url)
    request.setupRequest(headers: headers, authType: authType, contentType: contentType, method: .get)
    return request
  }

  static func putPatchPostRequest(
    _ url: URL, headers: [String: String]?, dataType: DataType,
    authType: AuthType, contentType: ContentType, method: HTTPMethod
  ) -> URLRequest {

    var request = URLRequest(url: url)
    request.setupRequest(headers: headers, authType: authType, contentType: contentType, method: method)
    request.httpBody = dataType.data
    return request

  }

  static func deleteRequest(
    _ url: URL, headers: [String: String]?, dataType: DataType,
    authType: AuthType, contentType: ContentType, method: HTTPMethod
  ) -> URLRequest {

      var request = URLRequest(url: url)
      request.setupRequest(headers: headers, authType: authType, contentType: contentType, method: method)
      request.httpBody = dataType.data
      return request

  }

  public static func build(
    baseURL: URL, method: HTTPMethod, headers: [String: String]? = nil,
    authType: AuthType, path: String, contentType: ContentType,
    dataType: DataType, urlQueryItems: [URLQueryItem]? = nil
  ) -> Self {

    var url = baseURL
    url.appendPathComponent(path)

    return .init(
      baseURL: baseURL, path: path, method: method, headers: headers,
      authType: authType, contentType: contentType, dataType: dataType
    ) { () -> URLRequest in

      switch method {

      case .get:

        return getRequest(
          url, headers: headers, dataType: dataType, authType: authType,
          contentType: contentType, method: .get
        )

      case .put, .patch, .post:

        return putPatchPostRequest(
          url, headers: headers, dataType: dataType, authType: authType,
          contentType: contentType, method: method
        )

      case .delete:
        return deleteRequest(
          url, headers: headers, dataType: dataType, authType: authType,
          contentType: contentType, method: method
        )
      }
    }
  }

  public func send<D: Decodable, S: Scheduler>(
    urlSession: URLSession = URLSession.shared,
    jsonDecoder: JSONDecoder = .ISO8601JSONDecoder,
    scheduler: S
  ) -> AnyPublisher<D, HTTPError> {

    let request: URLRequest = urlRequest()

    return urlSession.dataTaskPublisher(for: request)
      .assumeHTTP()
      .responseData()
      .decoding(D.self, decoder: jsonDecoder)
      .catch { (error: HTTPError) -> AnyPublisher<D, HTTPError> in
        return Fail(error: error).eraseToAnyPublisher()
      }
      .receive(on: scheduler)
      .eraseToAnyPublisher()
  }
}

extension HttpRequest {
  var pathAppendedURL: URL {
    var url = baseURL
    url.appendPathComponent(path)
    return url
  }
}
