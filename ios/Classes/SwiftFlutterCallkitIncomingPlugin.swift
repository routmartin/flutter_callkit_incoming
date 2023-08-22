import AVFoundation
import CallKit
import Flutter
import UIKit

@available(iOS 10.0, *)
public class SwiftFlutterCallkitIncomingPlugin: NSObject, FlutterPlugin, CXProviderDelegate {
  static let ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP =
    "com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP"

  static let ACTION_CALL_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
  static let ACTION_CALL_START = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_START"
  static let ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
  static let ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
  static let ACTION_CALL_ENDED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
  static let ACTION_CALL_TIMEOUT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"
  static let ACTION_CALL_CUSTOM = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM"

  static let ACTION_CALL_TOGGLE_HOLD = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD"
  static let ACTION_CALL_TOGGLE_MUTE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE"
  static let ACTION_CALL_TOGGLE_DMTF = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF"
  static let ACTION_CALL_TOGGLE_GROUP =
    "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP"
  static let ACTION_CALL_TOGGLE_AUDIO_SESSION =
    "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION"

  @objc public private(set) static var sharedInstance: SwiftFlutterCallkitIncomingPlugin!

  private var streamHandlers: WeakArray<EventCallbackHandler> = WeakArray([])

  private var callManager: CallManager

  private var sharedProvider: CXProvider?

  private var outgoingCall: Call?
  private var answerCall: Call?

  private var data: Data?
  private var isFromPushKit: Bool = false
  private let devicePushTokenVoIP = "DevicePushTokenVoIP"

  private func sendEvent(_ event: String, _ body: [String: Any?]?) {
    streamHandlers.reap().forEach { handler in
      handler?.send(event, body ?? [:])
    }
  }

  @objc public func sendEventCustom(_ event: String, body: NSDictionary?) {
    streamHandlers.reap().forEach { handler in
      handler?.send(event, body ?? [:])
    }
  }

  public static func sharePluginWithRegister(with registrar: FlutterPluginRegistrar) {
    if sharedInstance == nil {
      sharedInstance = SwiftFlutterCallkitIncomingPlugin(messenger: registrar.messenger())
    }
    sharedInstance.shareHandlers(with: registrar)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    sharePluginWithRegister(with: registrar)
  }

  private static func createMethodChannel(messenger: FlutterBinaryMessenger) -> FlutterMethodChannel
  {
    return FlutterMethodChannel(name: "flutter_callkit_incoming", binaryMessenger: messenger)
  }

  private static func createEventChannel(messenger: FlutterBinaryMessenger) -> FlutterEventChannel {
    return FlutterEventChannel(name: "flutter_callkit_incoming_events", binaryMessenger: messenger)
  }

  public init(messenger: FlutterBinaryMessenger) {
    callManager = CallManager()
  }

  private func shareHandlers(with registrar: FlutterPluginRegistrar) {
    registrar.addMethodCallDelegate(
      self, channel: Self.createMethodChannel(messenger: registrar.messenger()))
    let eventsHandler = EventCallbackHandler()
    streamHandlers.append(eventsHandler)
    Self.createEventChannel(messenger: registrar.messenger()).setStreamHandler(eventsHandler)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showCallkitIncoming":
      guard let args = call.arguments else {
        result("OK")
        return
      }
      if let getArgs = args as? [String: Any] {
        data = Data(args: getArgs)
        showCallkitIncoming(data!, fromPushKit: false)
      }
      result("OK")
      break
    case "showMissCallNotification":
      result("OK")
      break
    case "startCall":
      guard let args = call.arguments else {
        result("OK")
        return
      }
      if let getArgs = args as? [String: Any] {
        data = Data(args: getArgs)
        startCall(data!, fromPushKit: false)
      }
      result("OK")
      break
    case "endCall":
      guard let args = call.arguments else {
        result("OK")
        return
      }
      if isFromPushKit {
        endCall(data!)
      } else {
        if let getArgs = args as? [String: Any] {
          data = Data(args: getArgs)
          endCall(data!)
        }
      }
      result("OK")
      break
    case "muteCall":
      guard let args = call.arguments as? [String: Any],
        let callId = args["id"] as? String,
        let isMuted = args["isMuted"] as? Bool
      else {
        result("OK")
        return
      }

      muteCall(callId, isMuted: isMuted)
      result("OK")
      break
    case "holdCall":
      guard let args = call.arguments as? [String: Any],
        let callId = args["id"] as? String,
        let onHold = args["isOnHold"] as? Bool
      else {
        result("OK")
        return
      }
      holdCall(callId, onHold: onHold)
      result("OK")
      break
    case "callConnected":
      guard let args = call.arguments else {
        result("OK")
        return
      }
      if isFromPushKit {
        connectedCall(data!)
      } else {
        if let getArgs = args as? [String: Any] {
          // data = Data(args: getArgs)
          connectedCall(data!)
        }
      }
      result("OK")
      break
    case "activeCalls":
      result(callManager.activeCalls())
      break
    case "endAllCalls":
      callManager.endCallAlls()
      result("OK")
      break
    case "removeActiveCall":
      removeActiveCall()
      result("OK")
      break
    case "getDevicePushTokenVoIP":
      result(getDevicePushTokenVoIP())
      break
    case "acceptCall":
      acceptCall(data!)
      break
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc public func setDevicePushTokenVoIP(_ deviceToken: String) {
    UserDefaults.standard.set(deviceToken, forKey: devicePushTokenVoIP)
    sendEvent(
      SwiftFlutterCallkitIncomingPlugin.ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP,
      ["deviceTokenVoIP": deviceToken])
  }

  @objc public func getDevicePushTokenVoIP() -> String {
    return UserDefaults.standard.string(forKey: devicePushTokenVoIP) ?? ""
  }

  @objc public func getAcceptedCall() -> Data? {
    NSLog(
      "Call data ids \(String(describing: data?.uuid)) \(String(describing: answerCall?.uuid.uuidString))"
    )
    if data?.uuid.lowercased() == answerCall?.uuid.uuidString.lowercased() {
      return data
    }
    return nil
  }

  @objc public func showCallkitIncoming(_ data: Data, fromPushKit: Bool) {
    isFromPushKit = fromPushKit
    if fromPushKit {
      self.data = data
    }

    var handle: CXHandle?
    handle = CXHandle(type: getHandleType(data.handleType), value: data.getEncryptHandle())

    let callUpdate = CXCallUpdate()
    callUpdate.remoteHandle = handle
    callUpdate.supportsDTMF = data.supportsDTMF
    callUpdate.supportsHolding = data.supportsHolding
    callUpdate.supportsGrouping = data.supportsGrouping
    callUpdate.supportsUngrouping = data.supportsUngrouping
    callUpdate.hasVideo = data.type > 0 ? true : false
    callUpdate.localizedCallerName = data.nameCaller

    initCallkitProvider(data)

    let uuid = UUID(uuidString: data.uuid)

    sharedProvider?.reportNewIncomingCall(with: uuid!, update: callUpdate) { error in
      if error == nil {
        let call = Call(uuid: uuid!, data: data)
        call.handle = data.handle
        self.callManager.addCall(call)
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, data.toJSON())
        self.endCallNotExist(data)
      }
    }
  }

  @objc public func startCall(_ data: Data, fromPushKit: Bool) {
    isFromPushKit = fromPushKit
    if fromPushKit {
      self.data = data
    }
    initCallkitProvider(data)
    callManager.startCall(data)
  }

  @objc public func muteCall(_ callId: String, isMuted: Bool) {
    guard let callId = UUID(uuidString: callId),
      let call = callManager.callWithUUID(uuid: callId)
    else {
      return
    }
    if call.isMuted == isMuted {
      sendMuteEvent(callId.uuidString, isMuted)
    } else {
      callManager.muteCall(call: call, isMuted: isMuted)
    }
  }

  @objc public func holdCall(_ callId: String, onHold: Bool) {
    guard let callId = UUID(uuidString: callId),
      let call = callManager.callWithUUID(uuid: callId)
    else {
      return
    }
    if call.isOnHold == onHold {
      sendMuteEvent(callId.uuidString, onHold)
    } else {
      callManager.holdCall(call: call, onHold: onHold)
    }
  }

  @objc public func endCall(_ data: Data) {
    var call: Call?
    if isFromPushKit {
      call = Call(uuid: UUID(uuidString: self.data!.uuid)!, data: data)
      isFromPushKit = false
      sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data.toJSON())
    } else {
      call = Call(uuid: UUID(uuidString: data.uuid)!, data: data)
    }
    callManager.endCall(call: call!)
  }

  @objc public func acceptCall(_ data: Data) {
    var call: Call?
    if isFromPushKit {
      call = Call(uuid: UUID(uuidString: self.data!.uuid)!, data: data)
      isFromPushKit = false
    } else {
      call = Call(uuid: UUID(uuidString: data.uuid)!, data: data)
    }
    callManager.acceptCall(call: call!)
  }

  @objc public func connectedCall(_ data: Data) {
    var call: Call?
    if isFromPushKit {
      call = Call(uuid: UUID(uuidString: self.data!.uuid)!, data: data)
      isFromPushKit = false
    } else {
      call = Call(uuid: UUID(uuidString: data.uuid)!, data: data)
    }
    callManager.connectedCall(call: call!)
  }

  @objc public func activeCalls() -> [[String: Any]] {
    return callManager.activeCalls()
  }

  @objc public func endAllCalls() {
    isFromPushKit = false
    callManager.endCallAlls()
  }

  @objc public func removeActiveCall() {
    isFromPushKit = false
    answerCall = nil
    callManager.removeAllCalls()
    callManager.endActiveCall()
  }

  public func saveEndCall(_ uuid: String, _ reason: Int) {
    switch reason {
    case 1:
      sharedProvider?.reportCall(
        with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.failed)
      break
    case 2, 6:
      sharedProvider?.reportCall(
        with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.remoteEnded)
      break
    case 3:
      sharedProvider?.reportCall(
        with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.unanswered)
      break
    case 4:
      sharedProvider?.reportCall(
        with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.answeredElsewhere)
      break
    case 5:
      sharedProvider?.reportCall(
        with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.declinedElsewhere)
      break
    default:
      break
    }
  }

  func endCallNotExist(_ data: Data) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(data.duration)) {
      let call = self.callManager.callWithUUID(uuid: UUID(uuidString: data.uuid)!)
      if call != nil && self.answerCall == nil && self.outgoingCall == nil {
        self.callEndTimeout(data)
      }
    }
  }

  func callEndTimeout(_ data: Data) {
    saveEndCall(data.uuid, 3)
    sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data.toJSON())
  }

  func getHandleType(_ handleType: String?) -> CXHandle.HandleType {
    var typeDefault = CXHandle.HandleType.generic
    switch handleType {
    case "number":
      typeDefault = CXHandle.HandleType.phoneNumber
      break
    case "email":
      typeDefault = CXHandle.HandleType.emailAddress
    default:
      typeDefault = CXHandle.HandleType.generic
    }
    return typeDefault
  }

  func initCallkitProvider(_ data: Data) {
    if sharedProvider == nil {
      sharedProvider = CXProvider(configuration: createConfiguration(data))
      sharedProvider?.setDelegate(self, queue: nil)
    }
    callManager.setSharedProvider(sharedProvider!)
  }

  func createConfiguration(_ data: Data) -> CXProviderConfiguration {
    let configuration = CXProviderConfiguration(localizedName: data.appName)
    configuration.supportsVideo = data.supportsVideo
    configuration.maximumCallGroups = data.maximumCallGroups
    configuration.maximumCallsPerCallGroup = data.maximumCallsPerCallGroup

    configuration.supportedHandleTypes = [
      CXHandle.HandleType.generic,
      CXHandle.HandleType.emailAddress,
      CXHandle.HandleType.phoneNumber,
    ]
    if #available(iOS 11.0, *) {
      configuration.includesCallsInRecents = data.includesCallsInRecents
    }
    if !data.iconName.isEmpty {
      if let image = UIImage(named: data.iconName) {
        configuration.iconTemplateImageData = image.pngData()
      } else {
        print("Unable to load icon \(data.iconName).")
      }
    }
    if !data.ringtonePath.isEmpty || data.ringtonePath != "system_ringtone_default" {
      configuration.ringtoneSound = data.ringtonePath
    }
    return configuration
  }

  public func providerDidReset(_ provider: CXProvider) {
    for call in callManager.calls {
      call.endCall()
    }
    callManager.removeAllCalls()
  }

  public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    let call = Call(uuid: action.callUUID, data: data!, isOutGoing: true)
    call.handle = action.handle.value

    call.hasStartedConnectDidChange = { [weak self] in
      self?.sharedProvider?.reportOutgoingCall(
        with: call.uuid, startedConnectingAt: call.connectData)
    }
    call.hasConnectDidChange = { [weak self] in
      self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
    }
    outgoingCall = call
    callManager.addCall(call)
    sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_START, data?.toJSON())
    action.fulfill()
  }

  public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
      action.fail()
      return
    }

    call.hasConnectDidChange = { [weak self] in
      self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
    }
    answerCall = call
    sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT, data?.toJSON())
    action.fulfill()
  }

  public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
      if answerCall == nil && outgoingCall == nil {
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data?.toJSON())
      } else {
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data?.toJSON())
      }
      action.fail()
      return
    }
    call.endCall()
    callManager.removeCall(call)
    if answerCall == nil && outgoingCall == nil {
      sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_DECLINE, data?.toJSON())
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        action.fulfill()
      }
    } else {
      answerCall = nil
      sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data?.toJSON())
      action.fulfill()
    }
  }

  public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
      action.fail()
      return
    }
    call.isOnHold = action.isOnHold
    call.isMuted = action.isOnHold
    callManager.setHold(call: call, onHold: action.isOnHold)
    sendHoldEvent(action.callUUID.uuidString, action.isOnHold)
    action.fulfill()
  }

  public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
      action.fail()
      return
    }
    call.isMuted = action.isMuted
    sendMuteEvent(action.callUUID.uuidString, action.isMuted)
    action.fulfill()
  }

  public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
    guard (callManager.callWithUUID(uuid: action.callUUID)) != nil else {
      action.fail()
      return
    }
    sendEvent(
      SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_GROUP,
      [
        "id": action.callUUID.uuidString,
        "callUUIDToGroupWith": action.callUUIDToGroupWith?.uuidString,
      ])
    action.fulfill()
  }

  public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
    guard (callManager.callWithUUID(uuid: action.callUUID)) != nil else {
      action.fail()
      return
    }
    sendEvent(
      SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_DMTF,
      ["id": action.callUUID.uuidString, "digits": action.digits, "type": action.type])
    action.fulfill()
  }

  public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data?.toJSON())
  }

  public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
  }

  public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    if outgoingCall?.isOnHold ?? false || answerCall?.isOnHold ?? false {
      print("Call is on hold")
      return
    }
    outgoingCall?.endCall()
    if outgoingCall != nil {
      outgoingCall = nil
    }
    answerCall?.endCall()
    if answerCall != nil {
      answerCall = nil
    }

    answerCall?.endCall()
    callManager.removeAllCalls()
  }

  private func sendMuteEvent(_ id: String, _ isMuted: Bool) {
    sendEvent(
      SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_MUTE, ["id": id, "isMuted": isMuted])
  }

  private func sendHoldEvent(_ id: String, _ isOnHold: Bool) {
    sendEvent(
      SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_HOLD, ["id": id, "isOnHold": isOnHold])
  }
}

class EventCallbackHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  public func send(_ event: String, _ body: Any) {
    let data: [String: Any] = [
      "event": event,
      "body": body,
    ]
    eventSink?(data)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
