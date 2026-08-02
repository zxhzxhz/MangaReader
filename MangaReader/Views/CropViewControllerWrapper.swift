import SwiftUI
import UIKit

struct CropViewControllerWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    func makeUIViewController(context: Context) -> TOCropViewController {
        let controller = TOCropViewController(croppingStyle: .default, image: image)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: TOCropViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onCrop: onCrop)
    }

    final class Coordinator: NSObject, TOCropViewControllerDelegate {
        let onCancel: () -> Void
        let onCrop: (UIImage) -> Void

        init(onCancel: @escaping () -> Void, onCrop: @escaping (UIImage) -> Void) {
            self.onCancel = onCancel
            self.onCrop = onCrop
        }

        func cropViewController(
            _ cropViewController: TOCropViewController,
            didCropToImage image: UIImage,
            withRect cropRect: CGRect,
            angle: Int
        ) {
            onCrop(image)
        }

        func cropViewController(
            _ cropViewController: TOCropViewController,
            didFinishCancelled cancelled: Bool
        ) {
            onCancel()
        }
    }
}
