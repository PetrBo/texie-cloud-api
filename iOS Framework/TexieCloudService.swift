//
//  TexieCloudService.swift
//  Ingredients
//
//  Created by Petr Bobak on 10.04.17.
//  Copyright © 2017 Petr Bobak. All rights reserved.
//

import UIKit
import Alamofire

class TexieCloudService: NSObject {

    private var clientId: String?
    private var clientSecret: String?
    
    private let hostURL = "http://gw-q201.fit.vutbr.cz:8081"
    private let tokenURL = "http://gw-q201.fit.vutbr.cz:8081/api/v1/oauth/token/"
    private let annotationURL = "http://gw-q201.fit.vutbr.cz:8081/api/v1/annotations/"
    private let revokeURL = "http://gw-q201.fit.vutbr.cz:8081/api/v1/oauth/revoke_token/"
    private var accessToken: String {
        get {
            let token = UserDefaults.standard.value(forKey: "access_token")
            if let token = token {
                return token as! String
            } else {
                return ""
            }
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "access_token")
        }
    }
    
    static let shared: TexieCloudService = {
        let instance = TexieCloudService()
        return instance
    }()
    
    /**
     Set client credentials for application created in Texie Cloud API dashboard.
     
     - Parameters:
        - id: Unique identification of given application.
        - secret: Secret key of given application.
     
     - Important:
        This method should be called from application(_:didFinishLaunchingWithOptions:) delegate method.
     */
    func setCredentials(clientId id: String, clientSecret secret: String) {
        clientId = id
        clientSecret = secret
    }
    
    /**
     Assemble the absolute path for given relative image URL.
     
     - Parameters:
        - image: Relative path to image.
     
     - Returns:
        Absolute image path using URL instance.
     */
    func imageURL(image: String) -> URL? {
        return URL(string: hostURL + image)
    }
    
    /**
     Get access token from service.
     
     - Parameters:
        - completion: Completion block.
     
     - Important:
        This method should be called after setCredentials(id:secret:) method.
     */
    func token(completion: ((_ token: String?, _ error: Error?) -> Void)?) {
        var headers: HTTPHeaders = [:]
        let parameters: Parameters = ["grant_type": "client_credentials"]
        
        if let id = clientId, let secret = clientSecret {
            if let authorizationHeader = Request.authorizationHeader(user: id, password: secret) {
                headers[authorizationHeader.key] = authorizationHeader.value
            }
        } else {
            print("Warning: client credentials were not provided.")
            if let completion = completion {
                completion(nil, nil)
            }
            return
        }
        
        Alamofire.request(tokenURL, method: .post, parameters: parameters, headers: headers).validate()
            .responseJSON { response in
                switch response.result {
                case .success:
                    
                    // Get JSON return value as Dictionary.
                    if let dictionary = response.result.value as? [String: Any] {
                        if let accessToken = dictionary["access_token"] as? String {
                            self.accessToken = accessToken
                            print("Token: \(accessToken)")
                            if let completion = completion {
                                completion(accessToken, nil)
                            }
                        }
                    }
                    
                case .failure(let error):
                    if let completion = completion {
                        completion(nil, error)
                    }
                }
        }
    }
    
    /**
     Get access token from service.
     
     - Important:
        This method should be called after setCredentials(id:secret:) method.
     */
    func token() {
        token(completion: nil)
    }
    
    /**
     Revoke current access token.
     
     - Parameters:
        - completion: Completion block.
     
     - Important:
        This method should be called after setCredentials(id:secret:) method.
     */
    func revoke(completion: ((_ error: Error?) -> Void)?) {
        guard let id = clientId else {
            print("Warning: client credentials were not provided.")
            if let completion = completion {
                completion(nil)
            }
            return
        }
        
        let parameters: Parameters = ["token": accessToken,
                                      "client_id": id,
                                      "token_type_hint": "access_token"
                                      ]
        
        Alamofire.request(revokeURL, method: .post, parameters: parameters).validate()
            .responseJSON { response in
                switch response.result {
                case .success:
                    if let completion = completion {
                        completion(nil)
                        self.accessToken = ""
                    }
                    
                case .failure(let error):
                    if let completion = completion {
                        completion(error)
                    }
                }
        }
    }
    
    /**
     Revoke current access token.

     - Important:
        This method should be called after setCredentials(id:secret:) method.
     */
    func revoke() {
        revoke(completion: nil)
    }
    
    /**
     Authenticate current application automatically.
     
     - Important:
        This method should be called from applicationDidBecomeActive(_:) delegate method.
     */
    func authenticate() {
        revoke()
        token()
    }
    
    /**
     Annotate the image using Texie Cloud API service.
     
     - Parameters:
        - image: Instance of UIImage that will be recognized.
        - store: Indicates if the image and result should be stored on server or not.
        - completion: Completion block.
     
     - Important:
        This method should be called after setCredentials(id:secret:) method.
     */
    func annnotate(image: UIImage , store: Bool = true, completion: @escaping ((_ text: String?, _ url: String?,  _ error: Error?) -> Void)) {
        
        // Convert instance of UIImage to Data.
        //let resizedImage = resize(image: image.fixOrientation(), scaledToWidth: 1440.0)
        let imageData = UIImageJPEGRepresentation(image.fixOrientation(), 0.3)
        
        let headers: HTTPHeaders = ["Authorization" : "Bearer " + accessToken]
        
        var annotationURLWithParams = annotationURL
        if !store {
            annotationURLWithParams += "?store=false"
        }
        
        Alamofire.upload(
            multipartFormData: { (multipartFormData) in
                multipartFormData.append(imageData!, withName: "image", fileName: "file.jpg", mimeType: "image/jpg")
            },
            to: annotationURLWithParams,
            headers: headers,
            encodingCompletion: { (encodingResult) in
                switch encodingResult {
                case .success(let upload, _, _):
                    upload.responseJSON { (response) in
                    
                        // Check the response status code.
                        if let status = response.response?.statusCode {
                            switch status {
                            case 201:
                                print("Image upload successful!")
                            default:
                                print("Image upload error with response status: \(status)")
                                completion(nil, nil, NSError(domain: "Image upload", code: 1001, userInfo: nil))
                                return
                            }
                        }
                    
                        // Get JSON return value as Dictionary.
                        if let dictionary = response.result.value as? [String: Any] {
                            if let text = dictionary["text"] as? String {
                                print("Recognised text: ", text)
                                if let url = dictionary["image"] as? String {
                                    completion(text, url, nil)
                                } else {
                                    completion(text, nil, nil)
                                }
                            }
                        } else {
                            print("Malformed data received!")
                            completion(nil, nil, NSError(domain: "Malformed data", code: 1000, userInfo: nil))
                        }
                    
                    }
                case .failure(let encodingError):
                    print(encodingError)
                    completion(nil, nil, encodingError)
                }
        })
    }
    
    private func resize(image:UIImage, scaledToWidth: CGFloat) -> UIImage {
        let oldWidth = image.size.width
        let scaleFactor = scaledToWidth / oldWidth
        
        let newHeight = image.size.height * scaleFactor
        let newWidth = oldWidth * scaleFactor
        
        UIGraphicsBeginImageContext(CGSize(width:newWidth, height:newHeight))
        image.draw(in: CGRect(x:0, y:0, width:newWidth, height:newHeight))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
}
