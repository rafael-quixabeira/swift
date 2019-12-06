//
//  HistoryRouter.swift
//
//  PubNub Real-time Cloud-Hosted Push API and Push Notification Client Frameworks
//  Copyright © 2019 PubNub Inc.
//  https://www.pubnub.com/
//  https://www.pubnub.com/terms
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

// MARK: - Router

struct HistoryRouter: HTTPRouter {
  // Nested Endpoint
  enum Endpoint: CustomStringConvertible {
    case fetchV2(channel: String, max: Int?, start: Timetoken?, end: Timetoken?, includeMeta: Bool)
    case fetchV3(channels: [String], max: Int?, start: Timetoken?, end: Timetoken?, includeMeta: Bool)
    case fetchWithActions(channel: String, max: Int?, start: Timetoken?, end: Timetoken?, includeMeta: Bool)
    case delete(channel: String, start: Timetoken?, end: Timetoken?)
    case messageCounts(channels: [String], timetoken: Timetoken?, channelsTimetoken: [Timetoken]?)

    var description: String {
      switch self {
      case .fetchV2:
        return "Fetch Message History V2"
      case .fetchV3:
        return "Fetch Message History"
      case .fetchWithActions:
        return "Fetch Message History with Message Actions"
      case .delete:
        return "Delete Message History"
      case .messageCounts:
        return "Message Counts"
      }
    }

    var firstChannel: String? {
      switch self {
      case .fetchV2(let channel, _, _, _, _):
        return channel
      case .fetchWithActions(let channel, _, _, _, _):
        return channel
      case .fetchV3(let channels, _, _, _, _):
        return channels.first
      case .delete(let channel, _, _):
        return channel
      case .messageCounts(let channels, _, _):
        return channels.first
      }
    }
  }

  // Init
  init(_ endpoint: Endpoint, configuration: RouterConfiguration) {
    self.endpoint = endpoint
    self.configuration = configuration
  }

  var endpoint: Endpoint
  var configuration: RouterConfiguration

  // Protocol Properties
  var service: PubNubService {
    return .history
  }

  var category: String {
    return endpoint.description
  }

  var path: Result<String, Error> {
    let path: String

    switch endpoint {
    case .fetchV2(let channel, _, _, _, _):
      path = "/v2/history/sub-key/\(subscribeKey)/channel/\(channel.urlEncodeSlash)"
    case .fetchWithActions(let channel, _, _, _, _):
      path = "/v3/history-with-actions/sub-key/\(subscribeKey)/channel/\(channel)"
    case .fetchV3(let channels, _, _, _, _):
      path = "/v3/history/sub-key/\(subscribeKey)/channel/\(channels.csvString.urlEncodeSlash)"
    case .delete(let channel, _, _):
      path = "/v3/history/sub-key/\(subscribeKey)/channel/\(channel.urlEncodeSlash)"
    case .messageCounts(let channels, _, _):
      path = "/v3/history/sub-key/\(subscribeKey)/message-counts/\(channels.csvString.urlEncodeSlash)"
    }
    return .success(path)
  }

  var queryItems: Result<[URLQueryItem], Error> {
    var query = defaultQueryItems

    switch endpoint {
    case let .fetchV2(_, max, start, end, includeMeta):
      query.appendIfPresent(key: .count, value: max?.description)
      query.appendIfPresent(key: .stringtoken, value: false.description)
      query.appendIfPresent(key: .includeToken, value: true.description)
      query.appendIfPresent(key: .reverse, value: false.description)
      query.appendIfPresent(key: .start, value: start?.description)
      query.appendIfPresent(key: .end, value: end?.description)
      query.appendIfPresent(key: .includeMeta, value: includeMeta.description)
    case let .fetchWithActions(_, max, start, end, includeMeta):
      query.appendIfPresent(key: .max, value: max?.description)
      query.appendIfPresent(key: .start, value: start?.description)
      query.appendIfPresent(key: .end, value: end?.description)
      query.appendIfPresent(key: .includeMeta, value: includeMeta.description)
    case let .fetchV3(_, max, start, end, includeMeta):
      query.appendIfPresent(key: .max, value: max?.description)
      query.appendIfPresent(key: .start, value: start?.description)
      query.appendIfPresent(key: .end, value: end?.description)
      query.appendIfPresent(key: .includeMeta, value: includeMeta.description)
    case let .delete(_, startTimetoken, endTimetoken):
      query.appendIfPresent(key: .start, value: startTimetoken?.description)
      query.appendIfPresent(key: .end, value: endTimetoken?.description)
    case let .messageCounts(parameters):
      query.appendIfPresent(key: .timetoken, value: parameters.timetoken?.description)
      query.appendIfPresent(key: .channelsTimetoken,
                            value: parameters.channelsTimetoken?.map { $0.description }.csvString)
    }

    return .success(query)
  }

  var method: HTTPMethod {
    switch endpoint {
    case .delete:
      return .delete
    default:
      return .get
    }
  }

  // Validated
  var validationErrorDetail: String? {
    switch endpoint {
    case .fetchV2(let channel, _, _, _, _):
      return isInvalidForReason((channel.isEmpty,
                                 ErrorDescription.emptyChannelString))
    case .fetchWithActions(let channel, _, _, _, _):
      return isInvalidForReason((channel.isEmpty, ErrorDescription.emptyChannelString))
    case .fetchV3(let channels, _, _, _, _):
      return isInvalidForReason((channels.isEmpty, ErrorDescription.emptyChannelArray))
    case let .delete(channel, _, _):
      return isInvalidForReason((channel.isEmpty, ErrorDescription.emptyChannelString))
    case let .messageCounts(channels, timetoken, timetokens):
      return isInvalidForReason(
        (channels.isEmpty, ErrorDescription.emptyChannelArray),
        (timetoken == nil && timetokens == nil, ErrorDescription.missingTimetoken),
        (channels.count != timetokens?.count && timetokens != nil,
         ErrorDescription.invalidHistoryTimetokens)
      )
    }
  }
}

// MARK: - Response Decoder

struct MessageHistoryResponseDecoder: ResponseDecoder {
  func decode(response: EndpointResponse<Data>) -> Result<EndpointResponse<MessageHistoryResponse>, Error> {
    do {
      // Version3
      if let version3Payload = try? Constant.jsonDecoder.decode(MessageHistoryResponse.self, from: response.payload) {
        let decodedResponse = EndpointResponse<MessageHistoryResponse>(router: response.router,
                                                                       request: response.request,
                                                                       response: response.response,
                                                                       data: response.data,
                                                                       payload: version3Payload)

        // Attempt to decode message response

        return .success(decodedResponse)
      }

      return try decodeMessageHistoryV2(response: response)
    } catch {
      return .failure(PubNubError(.jsonDataDecodingFailure, response: response, error: error))
    }
  }

  func decodeMessageHistoryV2(
    response: EndpointResponse<Data>
  ) throws -> Result<EndpointResponse<MessageHistoryResponse>, Error> {
    // Deprecated: Remove `countKey` with v2 message history
    let version2Payload = try Constant.jsonDecoder.decode(AnyJSON.self, from: response.payload).wrappedUnderlyingArray

    guard version2Payload.count == 3,
      let channelName = (response.router as? HistoryRouter)?.endpoint.firstChannel,
      let encodedMessages = version2Payload.first,
      let startTimetoken = version2Payload[1].underlyingValue as? Timetoken,
      let endTimetoken = version2Payload.last?.underlyingValue as? Timetoken else {
      return .failure(PubNubError(.malformedResponseBody, response: response))
    }

    let messages = try encodedMessages.decode([MessageHistoryMessagesPayload].self)

    let channels: [String: MessageHistoryChannelPayload]
    if !messages.isEmpty {
      let channelPayload = MessageHistoryChannelPayload(messags: messages,
                                                        startTimetoken: startTimetoken,
                                                        endTimetoken: endTimetoken)
      channels = [channelName: channelPayload]
    } else {
      channels = [:]
    }
    let historyResponse = MessageHistoryResponse(status: response.response.statusCode, channels: channels)

    let decodedResponse = EndpointResponse<MessageHistoryResponse>(router: response.router,
                                                                   request: response.request,
                                                                   response: response.response,
                                                                   data: response.data,
                                                                   payload: historyResponse)
    return .success(decodedResponse)
    // End Deprecation Block
  }

  func decrypt(
    response: EndpointResponse<MessageHistoryResponse>
  ) -> Result<EndpointResponse<MessageHistoryResponse>, Error> {
    // End early if we don't have a cipher key
    guard let crypto = response.router.configuration.cipherKey else {
      return .success(response)
    }

    let channels = response.payload.channels.mapValues { channel -> MessageHistoryChannelPayload in
      var messages = channel.messages
      for (index, message) in messages.enumerated() {
        // Convert base64 string into Data
        if let messageData = message.message.dataOptional {
          // If a message fails we just return the original and move on
          do {
            let decryptedPayload = try crypto.decrypt(encrypted: messageData).get()
            if let decodedString = String(bytes: decryptedPayload, encoding: .utf8) {
              messages[index] = MessageHistoryMessagesPayload(message: AnyJSON(reverse: decodedString),
                                                              timetoken: message.timetoken,
                                                              meta: message.meta)
            } else {
              // swiftlint:disable:next line_length
              PubNub.log.error("Decrypted History payload data failed to stringify for base64 encoded payload \(decryptedPayload.base64EncodedString())")
            }
          } catch {
            PubNub.log.error("History message failed to decrypt due to \(error)")
          }
        }
      }
      return MessageHistoryChannelPayload(messags: messages,
                                          startTimetoken: channel.startTimetoken,
                                          endTimetoken: channel.endTimetoken)
    }

    // Replace previous payload with decrypted one
    let decryptedPayload = MessageHistoryResponse(status: response.payload.status,
                                                  error: response.payload.error,
                                                  responseMessage: response.payload.responseMessage,
                                                  channels: channels)
    let decryptedResponse = EndpointResponse<MessageHistoryResponse>(router: response.router,
                                                                     request: response.request,
                                                                     response: response.response,
                                                                     data: response.data,
                                                                     payload: decryptedPayload)
    return .success(decryptedResponse)
  }
}

// MARK: - Response Body

public typealias MessageHistoryChannelsPayload = [String: MessageHistoryChannelPayload]

public struct MessageHistoryResponse: Codable {
  public let status: Int
  public let error: Bool
  public let responseMessage: String
  public let channels: MessageHistoryChannelsPayload

  enum CodingKeys: String, CodingKey {
    case responseMessage = "error_message"
    case error
    case status
    case channels
  }

  public init(
    status: Int = 200,
    error: Bool = false,
    responseMessage _: String = "",
    channels: MessageHistoryChannelsPayload = [:]
  ) {
    self.status = status
    self.error = error
    responseMessage = ""
    self.channels = channels
  }

  public init(from decoder: Decoder) throws {
    // Check if container is keyed or unkeyed
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = try container.decode(Int.self, forKey: .status)
    error = try container.decode(Bool.self, forKey: .error)
    responseMessage = try container.decode(String.self, forKey: .responseMessage)
    channels = try container.decodeIfPresent([String: MessageHistoryChannelPayload].self, forKey: .channels) ?? [:]
  }
}

public struct MessageHistoryChannelPayload: Codable {
  public let messages: [MessageHistoryMessagesPayload]
  public let startTimetoken: Timetoken
  public let endTimetoken: Timetoken

  public init(
    messags: [MessageHistoryMessagesPayload] = [],
    startTimetoken: Timetoken = 0,
    endTimetoken: Timetoken = 0
  ) {
    messages = messags
    self.startTimetoken = startTimetoken
    self.endTimetoken = endTimetoken
  }

  public init(from decoder: Decoder) throws {
    // Check if container is keyed or unkeyed
    var container = try decoder.unkeyedContainer()
    var decodedMessages = [MessageHistoryMessagesPayload]()
    while !container.isAtEnd {
      try decodedMessages.append(container.decode(MessageHistoryMessagesPayload.self))
    }

    messages = decodedMessages
    startTimetoken = decodedMessages.first?.timetoken ?? 0
    endTimetoken = decodedMessages.last?.timetoken ?? 0
  }

  var isEmpty: Bool {
    return messages.isEmpty
  }
}

public struct MessageHistoryMessagesPayload: Codable {
  public let message: AnyJSON
  public let timetoken: Timetoken
  public let meta: AnyJSON?
  public let actions: [MessageActionPayload]

  public init(message: AnyJSON, timetoken: Timetoken = 0, meta: AnyJSON? = nil, actions: [MessageActionPayload] = []) {
    self.message = message
    self.timetoken = timetoken
    self.meta = meta
    self.actions = actions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    message = try container.decode(AnyJSON.self, forKey: .message)
    meta = try container.decodeIfPresent(AnyJSON.self, forKey: .meta)
    var messageTimetoken: Timetoken = 0
    if let tokenNumber = try? Timetoken(container.decode(String.self, forKey: .timetoken)) {
      messageTimetoken = tokenNumber
    } else {
      messageTimetoken = try container.decode(Timetoken.self, forKey: .timetoken)
    }
    timetoken = messageTimetoken

    // [Type: [Value: [MessageActionHistory]]]
    let typeValueDictionary = try container.decodeIfPresent([String: [String: [MessageActionHistory]]].self,
                                                            forKey: .actions) ?? [:]
    var actions = [MessageActionPayload]()

    typeValueDictionary.forEach { actionType, valueDictionary in
      valueDictionary.forEach { actionValue, historyList in
        historyList.forEach { history in
          actions.append(MessageActionPayload(uuid: history.uuid,
                                              type: actionType,
                                              value: actionValue,
                                              actionTimetoken: history.actionTimetoken,
                                              messageTimetoken: messageTimetoken))
        }
      }
    }
    self.actions = actions
  }
}

struct MessageActionHistory: Codable {
  let uuid: String
  let actionTimetoken: Timetoken

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    uuid = try container.decode(String.self, forKey: .uuid)
    let timetoken = try container.decode(String.self, forKey: .actionTimetoken)
    actionTimetoken = Timetoken(timetoken) ?? 0
  }
}

// MARK: - Message Count

struct MessageCountsResponseDecoder: ResponseDecoder {
  typealias Payload = MessageCountsResponsePayload
}

public struct MessageCountsResponsePayload: Codable {
  let status: Int
  let error: Bool
  let errorMessage: String
  let channels: [String: Int]
  let more: [String: [String: AnyJSON]]

  enum CodingKeys: String, CodingKey {
    case status
    case error
    case errorMessage = "error_message"
    case channels
    case more
  }

  // swiftlint:disable:next file_length
}