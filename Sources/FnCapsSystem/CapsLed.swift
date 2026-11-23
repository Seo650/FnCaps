// 구조 참고: koutyuke/Capsaicin CapsLockLEDController.swift, pseudobun/hop StartupIndicator.swift (MIT)
import Foundation
import FnCapsCore
import IOKit
import IOKit.hidsystem

/// Caps Lock 표시등(`HIDCapsLockLED`)을 passive IOHIDEventSystemClient로 읽고 쓴다. 메인 스레드 전용.
///
/// simple 클라이언트(type 4, `hidutil`이 쓰는 종류)는 이 속성을 읽지도 쓰지도 못한다(이 Mac 실측).
/// 그래서 공개 헤더에 없는 `IOHIDEventSystemClientCreateWithType`을 `dlsym`으로 풀어 type 2를 만든다.
/// 리매퍼(Karabiner)의 가상 키보드는 `Transport`가 없거나 `Virtual`이므로 쓰지 않는다(T-07-04).
public final class CapsLed: CapsLedWriting {
    /// 복구 스크립트가 앱 본체 없이 부르는 인자. 값이 없고 `Auto`만 쓴다(D-04, D-07, T-07-02).
    public static let releaseArgument = "--release-caps-led"

    private static let ledProperty = "HIDCapsLockLED" as CFString
    private static let ledOnProperty = "HIDCapsLockLEDOn" as CFString
    /// 읽기 전용. 상태 표의 `svcState` 열에만 쓴다. 시스템 잠금을 쓰지 않는다(07-REVIEW WR-03).
    private static let stateProperty = "HIDCapsLockState" as CFString
    private static let transportProperty = "Transport" as CFString
    private static let builtInProperty = "Built-In" as CFString
    private static let productProperty = "Product" as CFString

    /// 공개 헤더에 없는 함수. 종류 2 = passive. 심볼이 없으면 표시등 기능만 끈다(T-07-01).
    private typealias CreateWithType = @convention(c) (CFAllocator?, Int32, CFDictionary?) -> Unmanaged<IOHIDEventSystemClient>?

    private static let createWithType: CreateWithType? = {
        // RTLD_DEFAULT. IOKit은 이미 링크되어 있으므로 별도 dlopen이 필요 없다.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventSystemClientCreateWithType")
        else { return nil }
        return unsafeBitCast(symbol, to: CreateWithType.self)
    }()

    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void = { _ in }) {
        self.log = log
    }

    // MARK: 쓰기

    /// `HIDCapsLockLED`만 쓴다. 시스템 잠금 상태(`HIDCapsLockState`)에는 쓰지 않는다(07-REVIEW WR-03).
    public func write(_ plan: CapsLedPlan) -> Int? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let kernel = KeyboardMapper.kernelKeyboardSet() else {
            log("led unsupported reason=noKernelSet")
            return nil
        }
        guard let client = makeClient() else { return nil }
        return withExtendedLifetime(client) {
            var written = 0
            for service in eligibleServices(client, kernel: kernel) {
                let value: CFTypeRef = plan.mode.rawValue as CFString
                // 쓰기 직후 다시 읽어 확인하지 않는다. 필터는 늦게 반영하고, 확인은 로그·눈으로 한다.
                if IOHIDServiceClientSetProperty(service, Self.ledProperty, value) { written += 1 }
            }
            return written
        }
    }

    public func release() -> Int? { write(.release) }

    // MARK: 상태 표(읽기 전용)

    /// 키보드 서비스 하나의 표시등 관련 값.
    public struct ServiceRow: Sendable {
        public let registryID: UInt64
        public let builtIn: Bool
        public let transport: String?
        public let product: String?
        /// 지금 불이 켜졌는지(`On`/`Off`). 모드가 아니다.
        public let led: String?
        public let ledOn: Bool?
        public let svcState: Bool?
        /// 이 앱이 쓰기 대상으로 고를 서비스인가.
        public let eligible: Bool
    }

    /// 키보드 서비스를 모두 읽어 표로 낸다. 쓰지 않는다.
    public func status() -> [ServiceRow]? {
        dispatchPrecondition(condition: .onQueue(.main))
        let kernel = KeyboardMapper.kernelKeyboardSet()
        guard let client = makeClient() else { return nil }
        return withExtendedLifetime(client) {
            let all = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
            return all.compactMap { service -> ServiceRow? in
                guard IOHIDServiceClientConformsTo(service, 1, 6) != 0,
                    let id = Self.registryID(of: service)
                else { return nil }
                let transport = Self.string(service, Self.transportProperty)
                // 쓰기 대상 규칙과 같은 함수를 쓴다(가상 키보드와 커널 목록 밖 제외).
                let eligible = CapsLedTarget.isEligible(
                    isKeyboard: true, transport: transport, registryID: id, kernel: kernel)
                return ServiceRow(
                    registryID: id,
                    builtIn: Self.number(service, Self.builtInProperty) ?? false,
                    transport: transport,
                    product: Self.string(service, Self.productProperty),
                    led: Self.string(service, Self.ledProperty),
                    ledOn: Self.number(service, Self.ledOnProperty),
                    svcState: Self.number(service, Self.stateProperty),
                    eligible: eligible)
            }
        }
    }

    // MARK: 서비스 고르기

    /// 매 호출마다 클라이언트를 새로 만든다. 서비스가 다시 만들어지면 옛 목록에 쓴 값이 닿지 않는다.
    private func makeClient() -> IOHIDEventSystemClient? {
        guard let create = Self.createWithType else {
            log("led unsupported reason=noSymbol")
            return nil
        }
        guard let client = create(kCFAllocatorDefault, 2, nil)?.takeRetainedValue() else {
            log("led unsupported reason=noClient")
            return nil
        }
        return client
    }

    /// 키보드(ConformsTo 1,6)이고 `CapsLedTarget.isEligible`을 통과한 서비스. 매핑과 같은 커널 키보드 집합에 든다.
    private func eligibleServices(_ client: IOHIDEventSystemClient, kernel: Set<UInt64>) -> [IOHIDServiceClient] {
        let all = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
        return all.filter { service in
            CapsLedTarget.isEligible(
                isKeyboard: IOHIDServiceClientConformsTo(service, 1, 6) != 0,
                transport: Self.string(service, Self.transportProperty),
                registryID: Self.registryID(of: service),
                kernel: kernel)
        }
    }

    private static func registryID(of service: IOHIDServiceClient) -> UInt64? {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
    }

    private static func string(_ service: IOHIDServiceClient, _ key: CFString) -> String? {
        IOHIDServiceClientCopyProperty(service, key) as? String
    }

    private static func number(_ service: IOHIDServiceClient, _ key: CFString) -> Bool? {
        (IOHIDServiceClientCopyProperty(service, key) as? NSNumber)?.boolValue
    }
}
