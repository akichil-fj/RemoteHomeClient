//
//  ApiClient.swift
//  RemoteHome
//
//  Created by 藤本 章良 on 2021/09/08.
//

import Foundation

protocol ApiClientProtocol {
    func fetchApplianceList(completion: @escaping (Result<[Appliance], Error>) -> Void)
    func fetchOperationList(appliance: String, completion: @escaping (Result<[Operation], Error>) -> Void)
    func postOperation(appliance: String, operation: String, completion: @escaping (Result<String, Error>) -> Void)
}

class ApiClient: ApiClientProtocol {
    
    var settingsModel = SettingsModel()
    
    func fetchApplianceList(completion: @escaping (Result<[Appliance], Error>) -> Void) {
        guard let host = settingsModel.fetchURL() else { return }
        if host == "" { return }
        let urlString = host + "/api/v1/list"
        guard let url = URL(string: urlString) else {
            completion(.failure(ApiError.wrongUrl))
            return
        }
        URLSession.shared.dataTask(with: url) { [self] (data, response, error) in
            if let error = error {
                handleURLError(error: error, completion: completion)
                return
            }
            guard let data = data else { return }
            guard let response = response as? HTTPURLResponse else { return }
            if response.statusCode != 200 {
                handleError(data: data, response: response, completion: completion)
                return
            }
            
            let decoder: JSONDecoder = JSONDecoder()
            do {
                let applianceListData = try decoder.decode([Appliance].self, from: data)
                DispatchQueue.main.async {
                    completion(.success(applianceListData))
                }
            } catch {
                print("json convert failed in JSONDecoder. " + error.localizedDescription)
                completion(.failure(ApiError.decoder(error)))
            }
        }.resume()
    }
    
    func fetchOperationList(appliance: String, completion: @escaping (Result<[Operation], Error>) -> Void) {
        guard let host = settingsModel.fetchURL() else { return }
        if host == "" { return }
        let urlString = host + "/api/v1/" + appliance
        guard let url = URL(string: urlString) else {
            completion(.failure(ApiError.wrongUrl))
            return
        }
        URLSession.shared.dataTask(with: url) { [self] (data, response, error) in
            if let error = error {
                handleURLError(error: error, completion: completion)
                return
            }
            guard let data = data else { return }
            guard let response = response as? HTTPURLResponse else { return }
            if response.statusCode != 200 {
                handleError(data: data, response: response, completion: completion)
                return
            }
            
            let decoder: JSONDecoder = JSONDecoder()
            do {
                let operationListData = try decoder.decode([Operation].self, from: data)
                DispatchQueue.main.async {
                    completion(.success(operationListData))
                }
            } catch {
                print("json convert failed in JSONDecoder. " + error.localizedDescription)
                completion(.failure(ApiError.decoder(error)))
            }
        }.resume()
    }
    
    func postOperation(appliance: String, operation: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let host = settingsModel.fetchURL() else { return }
        if host == "" { return }
        let urlString = host + "/api/v1/" + appliance + "/" + operation
        guard let url = URL(string: urlString) else {
            completion(.failure(ApiError.wrongUrl))
            return
        }
        var request = URLRequest(url: url)
        let passPhrase = settingsModel.fetchPassPhrase()
        let jsonBody = ["passphrase" : passPhrase]
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
            request.httpMethod = "POST"      // Send POST request
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
        } catch {
            print("json convert failed in JSONSerialization. " + error.localizedDescription)
            completion(.failure(ApiError.decoder(error)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [self] (data, response, error) in
            if let error = error {
                handleURLError(error: error, completion: completion)
                return
            }
            guard let data = data else { return }
            guard let response = response as? HTTPURLResponse else { return }
            if response.statusCode != 200 {
                handleError(data: data, response: response, completion: completion)
                return
            }
            
            let value = String(data: data, encoding: .utf8)!
            if value == "OK" {
                completion(.success(value))
                return
            }
        }.resume()
    }
    
    private func handleURLError<T>(error: Error, completion: @escaping (Result<T, Error>) -> Void) {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorCannotFindHost:
            completion(.failure(ApiError.wrongUrl))
        case NSURLErrorTimedOut:
            completion(.failure(ApiError.timeOut))
        default:
            completion(.failure(ApiError.unknown(error)))
        }
    }
    
    private func handleError<T>(data: Data, response: HTTPURLResponse, completion: @escaping (Result<T, Error>) -> Void) {
        let decoder: JSONDecoder = JSONDecoder()
        do {
            let apiErrorData = try decoder.decode(ApiErrorModel.self, from: data)
            let errorMessage = apiErrorData.error.message
            print(apiErrorData.error.message)
            completion(.failure(ApiError.server(response.statusCode, errorMessage)))
        } catch {
            print("json convert failed in JSONDecoder. " + error.localizedDescription)
            completion(.failure(ApiError.server(response.statusCode, "")))
        }
    }
    
}

protocol ConcurrncyApiClientProtocol {
    func fetchApplianceList() async -> Result<[Appliance], Error>
    func fetchOperationList(appliance: String) async -> Result<[Operation], Error>
    func postOperation(appliance: String, operation: String) async -> Result<String, Error>
}

class ConcurrncyApiClient: ConcurrncyApiClientProtocol {
    
    var settingsModel = SettingsModel()
    
    func fetchApplianceList() async -> Result<[Appliance], Error> {
        guard let url = createURL(path: "/api/v1/list") else { return .failure(ApiError.wrongUrl) }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse else { throw ApiError.noResponse }
            if response.statusCode != 200 {
                return handleServerError(data: data, response: response)
            }
            
            let decoder: JSONDecoder = JSONDecoder()
            do {
                let applianceListData = try decoder.decode([Appliance].self, from: data)
                return .success(applianceListData)
            } catch {
                print("json convert failed in JSONDecoder. " + error.localizedDescription)
                return .failure(ApiError.decoder(error))
            }
        } catch {
            return handleConnectionError(error: error)
        }
    }
    
    func fetchOperationList(appliance: String) async -> Result<[Operation], Error> {
        guard let url = createURL(path: "/api/v1/" + appliance) else { return .failure(ApiError.wrongUrl) }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse else { throw ApiError.noResponse }
            if response.statusCode != 200 {
                return handleServerError(data: data, response: response)
            }
            
            let decoder: JSONDecoder = JSONDecoder()
            do {
                let operationListData = try decoder.decode([Operation].self, from: data)
                return .success(operationListData)
            } catch {
                print("json convert failed in JSONDecoder. " + error.localizedDescription)
                return .failure(ApiError.decoder(error))
            }
        } catch {
            return handleConnectionError(error: error)
        }
    }
    
    func postOperation(appliance: String, operation: String) async -> Result<String, Error> {
        guard let url = createURL(path: "/api/v1/" + appliance + "/" + operation) else { return .failure(ApiError.wrongUrl) }
        
        var request = URLRequest(url: url)
        let passPhrase = settingsModel.fetchPassPhrase()
        let jsonBody = ["passphrase" : passPhrase]
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
            request.httpMethod = "POST"      // Send POST request
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
        } catch {
            print("json convert failed in JSONSerialization. " + error.localizedDescription)
            return .failure(ApiError.decoder(error))
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .failure(ApiError.noResponse) }
            if response.statusCode != 200 {
                return handleServerError(data: data, response: response)
            }
            let value = String(data: data, encoding: .utf8)!
            if value == "OK" {
                return .success(value)
            }
            return .failure(ApiError.badResponse)
        } catch {
            return handleConnectionError(error: error)
        }
    }
    
    private func createURL(path: String) -> URL? {
        guard let host = settingsModel.fetchURL() else { return nil }
        if host == "" { return nil }
        guard let url = URL(string: host) else { return nil }
        return url.appendingPathComponent(path)
    }
    
    private func handleConnectionError<T>(error: Error) -> (Result<T, Error>){
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorCannotFindHost:
            return .failure(ApiError.wrongUrl)
        case NSURLErrorTimedOut:
            return .failure(ApiError.timeOut)
        default:
            return .failure(ApiError.unknown(error))
        }
    }
    
    private func handleServerError<T>(data: Data, response: HTTPURLResponse) -> (Result<T, Error>) {
        let decoder: JSONDecoder = JSONDecoder()
        do {
            let apiErrorData = try decoder.decode(ApiErrorModel.self, from: data)
            let errorMessage = apiErrorData.error.message
            print(apiErrorData.error.message)
            return .failure(ApiError.server(response.statusCode, errorMessage))
        } catch {
            print("json convert failed in JSONDecoder. " + error.localizedDescription)
            return .failure(ApiError.server(response.statusCode, ""))
        }
    }
    
}
