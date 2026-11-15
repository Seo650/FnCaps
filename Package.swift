// swift-tools-version:5.9
import PackageDescription

// 공개 저장소용 매니페스트. 개발용 Package.swift에서 스파이크 타깃과 그 시험 타깃,
// 스파이크 실행 제품만 뺀 것이다(RESEARCH Q5). 나머지 줄은 개발용과 같게 유지한다.
// publish-public.sh가 이 파일을 공개 사본의 Package.swift로 복사한다.
let package = Package(
    name: "FnCaps",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FnCapsCore", targets: ["FnCapsCore"]),
        .library(name: "FnCapsSystem", targets: ["FnCapsSystem"]),
        .executable(name: "FnCaps", targets: ["FnCaps"])
    ],
    targets: [
        .target(name: "FnCapsCore"),
        .target(
            name: "FnCapsSystem",
            dependencies: ["FnCapsCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "FnCaps",
            dependencies: ["FnCapsCore", "FnCapsSystem"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(name: "FnCapsCoreTests", dependencies: ["FnCapsCore", "FnCapsSystem"])
    ]
)
