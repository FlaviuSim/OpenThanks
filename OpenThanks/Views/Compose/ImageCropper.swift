import SwiftUI
import UIKit

enum ImageProcessing {
    /// Decode and shrink an image off the main thread for cropping/upload.
    static func prepareForEditing(_ data: Data, maxDimension: CGFloat = 2048) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data)?.normalizedOrientation() else { return nil }
            return image.downsampled(maxDimension: maxDimension)
        }.value
    }

    static func jpegForUpload(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        image.downsampled(maxDimension: maxDimension).jpegData(compressionQuality: quality)
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

/// Pinch-zoom cropper backed by `UIScrollView` (reliable crop rect math).
struct ImageCropperView: UIViewControllerRepresentable {
    let image: UIImage
    /// Width / height. Feed photos use 4:3.
    var aspectRatio: CGFloat = 4 / 3
    var onCancel: () -> Void
    var onCrop: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let crop = ImageCropViewController(image: image, aspectRatio: aspectRatio)
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

    init(image: UIImage, aspectRatio: CGFloat) {
        self.image = image
        self.aspectRatio = aspectRatio
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Crop Photo"
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

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)

        dimView.isUserInteractionEnabled = false
        view.addSubview(dimView)

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
        scrollView.frame = view.bounds
        updateCropFrame()
        if imageView.bounds == .zero {
            layoutImage()
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
        cropBorder.frame = cropFrame
    }

    private func layoutImage() {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, cropFrame.width > 0 else { return }

        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        // Fill the crop rect (aspect fill).
        let fillScale = max(cropFrame.width / imageSize.width, cropFrame.height / imageSize.height)
        scrollView.minimumZoomScale = fillScale
        scrollView.maximumZoomScale = max(fillScale * 4, 4)
        scrollView.zoomScale = fillScale

        // Center image in crop frame via content inset.
        recenter()
    }

    private func recenter() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let horizontal = max(0, (boundsSize.width - contentSize.width) / 2)
        let vertical = max(0, (boundsSize.height - contentSize.height) / 2)

        // Keep crop window filled: insets so the visible crop maps to content.
        let top = cropFrame.minY
        let left = cropFrame.minX
        let bottom = boundsSize.height - cropFrame.maxY
        let right = boundsSize.width - cropFrame.maxX

        scrollView.contentInset = UIEdgeInsets(
            top: top + vertical,
            left: left + horizontal,
            bottom: bottom + vertical,
            right: right + horizontal
        )

        // Initial offset so image fills the crop centered.
        let offsetX = -left + (contentSize.width - cropFrame.width) / 2
        let offsetY = -top + (contentSize.height - cropFrame.height) / 2
        scrollView.contentOffset = CGPoint(x: max(offsetX, -left), y: max(offsetY, -top))
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
        let top = cropFrame.minY
        let left = cropFrame.minX
        let bottom = boundsSize.height - cropFrame.maxY
        let right = boundsSize.width - cropFrame.maxX
        scrollView.contentInset = UIEdgeInsets(
            top: top + vertical,
            left: left + horizontal,
            bottom: bottom + vertical,
            right: right + horizontal
        )
    }

    @objc private func cancelTapped() { onCancel?() }

    @objc private func useTapped() {
        onCrop?(croppedImage())
    }

    private func croppedImage() -> UIImage {
        // Convert the on-screen crop frame into image-view coordinates.
        let rectInImage = view.convert(cropFrame, to: imageView)
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
