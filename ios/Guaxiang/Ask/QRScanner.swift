#if DEVTOOLS
    import AVFoundation
    import SwiftUI
    import VisionKit

    /// 掃電腦上的 QR code（連 Claude CLI 用）。只認 QR code，掃到第一個就交出去。
    /// 模擬器沒有這個功能，畫面要改成貼網址
    struct QRScanner: UIViewControllerRepresentable {
        let onFound: (String) -> Void

        static var isSupported: Bool { DataScannerViewController.isSupported }

        /// 還沒問過相機就先問。能掃才回 true
        static func prepare() async -> Bool {
            guard isSupported else { return false }
            return await AVCaptureDevice.requestAccess(for: .video)
        }

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let controller = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
            controller.delegate = context.coordinator
            // 畫面還沒出來時開相機會失敗，等下一輪再開
            DispatchQueue.main.async {
                try? controller.startScanning()
            }
            return controller
        }

        func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

        static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
            controller.stopScanning()
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onFound: onFound)
        }

        @MainActor
        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onFound: (String) -> Void
            private var done = false

            init(onFound: @escaping (String) -> Void) {
                self.onFound = onFound
            }

            func dataScanner(
                _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                allItems: [RecognizedItem]
            ) {
                guard !done else { return }
                for item in addedItems {
                    if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                        done = true
                        onFound(text)
                        return
                    }
                }
            }
        }
    }
#endif
