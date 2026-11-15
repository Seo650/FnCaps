import Foundation

/// SwiftUI에서는 Text(verbatim:) / Toggle(String, isOn:)와 함께 쓴다.
/// SwiftUI LocalizedStringKey 조회(A12 미확인)에 기대지 않기 위한 헬퍼다.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// 인자 여러 개와 위치 지정자(%1$@, %2$@)를 받는다.
func LF(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }
