import SwiftUI
import UIKit

enum ImageProcessing {
    /// Long-edge cap for post photos — sharp on phone/web, small enough to load fast.
    static let postMaxDimension: CGFloat = 1280
    static let postJPEGQuality: CGFloat = 0.72
    /// Profile avatars are shown small; keep files tiny.
    static let avatarMaxDimension: CGFloat = 720
    static let avatarJPEGQuality: CGFloat = 0.78

    /// Decode and shrink an image off the main thread for cropping/upload.
    static func prepareForEditing(_ data: Data, maxDimension: CGFloat = 1600) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data)?.normalizedOrientation() else { return nil }
            return image.downsampled(maxDimension: maxDimension)
        }.value
    }

    static func jpegForUpload(
        _ image: UIImage,
        maxDimension: CGFloat = postMaxDimension,
        quality: CGFloat = postJPEGQuality
    ) -> Data? {
        image.downsampled(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    static func jpegForAvatar(_ image: UIImage) -> Data? {
        jpegForUpload(image, maxDimension: avatarMaxDimension, quality: avatarJPEGQuality)
    }
}

extension UIImage {
    func downsampled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Flatten EXIF orientation so crop math matches what’s on screen.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Pinch-zoom cropper. Scroll view is clipped to the crop window so pinching
/// does not scale the surrounding chrome. Aspect follows the source image
/// (tall and wide photos keep their shape).
struct ImageCropperView: UIViewControllerRepresentable {
    let image: UIImage
    var onCancel: () -> Void
    var onCrop: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let crop = ImageCropViewController(image: image)
        crop.onCancel = onCancel
        crop.onCrop = onCrop
        let nav = UINavigationController(rootViewController: crop)
        nav.navigationBar.prefersLargeTitles = false
        nav.overrideUserInterfaceStyle = .dark
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let crop = uiViewController.viewControllers.first as? ImageCropViewController {
            crop.onCancel = onCancel
            crop.onCrop = onCrop
        }
    }
}

final class ImageCropViewController: UIViewController, UIScrollViewDelegate {
    var onCancel: (() -> Void)?
    var onCrop: ((UIImage) -> Void)?

    private let image: UIImage
    private let aspectRatio: CGFloat
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let dimView = UIView()
    private let cropBorder = UIView()
    private var cropFrame = CGRect.zero
    private var didLayoutImage = false

    init(image: UIImage) {
        self.image = image
        let size = image.size
        self.aspectRatio = size.height > 0 ? size.width / size.height : 1
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Adjust Photo"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Use Photo", style: .done, target: self, action: #selector(useTapped)
        )

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = true

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        dimView.isUserInteractionEnabled = false
        view.addSubview(dimView)
        // Scroll view sits above the dim mask but is clipped to the crop window.
        view.addSubview(scrollView)

        cropBorder.isUserInteractionEnabled = false
        cropBorder.layer.borderColor = UIColor.white.cgColor
        cropBorder.layer.borderWidth = 1.5
        view.addSubview(cropBorder)

        let hint = UILabel()
        hint.text = "Pinch to zoom · drag to reposition"
        hint.textColor = UIColor.white.withAlphaComponent(0.7)
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCropFrame()
        scrollView.frame = cropFrame
        cropBorder.frame = cropFrame
        if !didLayoutImage {
            layoutImage()
            didLayoutImage = true
        }
        updateDimMask()
    }

    private func updateCropFrame() {
        let inset: CGFloat = 24
        let top = view.safeAreaInsets.top + 12
        let bottom = view.safeAreaInsets.bottom + 48
        let available = CGRect(
            x: inset,
            y: top,
            width: view.bounds.width - inset * 2,
            height: view.bounds.height - top - bottom
        )
        var size = available.size
        if size.width / size.height > aspectRatio {
            size = CGSize(width: size.height * aspectRatio, height: size.height)
        } else {
            size = CGSize(width: size.width, height: size.width / aspectRatio)
        }
        cropFrame = CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func layoutImage() {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, cropFrame.width > 0 else { return }

        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        // Fill the crop window (aspect fill) using the photo’s own proportions.
        let fillScale = max(cropFrame.width / imageSize.width, cropFrame.height / imageSize.height)
        scrollView.minimumZoomScale = fillScale
        scrollView.maximumZoomScale = max(fillScale * 4, 4)
        scrollView.zoomScale = fillScale
        recenter()
    }

    private func recenter() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let horizontal = max(0, (boundsSize.width - contentSize.width) / 2)
        let vertical = max(0, (boundsSize.height - contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)

        let offsetX = max((contentSize.width - boundsSize.width) / 2, -horizontal)
        let offsetY = max((contentSize.height - boundsSize.height) / 2, -vertical)
        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    private func updateDimMask() {
        dimView.frame = view.bounds
        dimView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let path = UIBezierPath(rect: dimView.bounds)
        path.append(UIBezierPath(rect: cropFrame))
        path.usesEvenOddFillRule = true

        let fill = CAShapeLayer()
        fill.path = path.cgPath
        fill.fillRule = .evenOdd
        fill.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        dimView.layer.addSublayer(fill)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let horizontal = max(0, (boundsSize.width - contentSize.width) / 2)
        let vertical = max(0, (boundsSize.height - contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func cancelTapped() { onCancel?() }

    @objc private func useTapped() {
        onCrop?(croppedImage())
    }

    private func croppedImage() -> UIImage {
        let rectInImage = scrollView.convert(scrollView.bounds, to: imageView)
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0,
              imageView.bounds.width > 0, imageView.bounds.height > 0,
              let cgImage = image.cgImage else { return image }

        let scaleX = imageSize.width / imageView.bounds.width
        let scaleY = imageSize.height / imageView.bounds.height
        let cropInImage = CGRect(
            x: rectInImage.origin.x * scaleX,
            y: rectInImage.origin.y * scaleY,
            width: rectInImage.width * scaleX,
            height: rectInImage.height * scaleY
        ).intersection(CGRect(origin: .zero, size: imageSize))

        guard cropInImage.width > 1, cropInImage.height > 1 else { return image }

        let pixelScale = image.scale
        let pixelRect = CGRect(
            x: cropInImage.origin.x * pixelScale,
            y: cropInImage.origin.y * pixelScale,
            width: cropInImage.width * pixelScale,
            height: cropInImage.height * pixelScale
        ).integral

        guard let cut = cgImage.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cut, scale: pixelScale, orientation: .up)
    }
}
