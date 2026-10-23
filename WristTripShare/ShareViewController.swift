import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private var providers: [NSItemProvider] = []
    private var isImporting = false
    private var didStartImport = false
    private var hasSavedImage = false
    private var isLaunchPending = false
    private var launchAttemptID = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { provider in
                provider.canLoadObject(ofClass: UIImage.self) ||
                    provider.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: .image) == true }
            }

        statusLabel.text = providers.isEmpty ? "图片接收失败：分享内容中没有图片。" : "正在接收图片…"
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        retryButton.setTitle("重试", for: .normal)
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        retryButton.isHidden = true
        doneButton.setTitle("完成", for: .normal)
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)
        doneButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [statusLabel, retryButton, doneButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        preferredContentSize = CGSize(width: 340, height: 180)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartImport, !providers.isEmpty else { return }
        didStartImport = true
        importImages()
    }

    @objc private func importImages() {
        guard !isImporting else { return }
        isImporting = true
        retryButton.isHidden = true
        statusLabel.text = "正在接收图片…"

        let group = DispatchGroup()
        let lock = NSLock()
        var receivedImages: [(index: Int, data: Data)] = []
        var errors: [String] = []
        for (index, provider) in providers.enumerated() {
            group.enter()
            Self.loadImageData(from: provider) { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    lock.lock()
                    receivedImages.append((index, data))
                    lock.unlock()
                case .failure(let error):
                    lock.lock()
                    errors.append("第 \(index + 1) 张图片接收失败：\(error.localizedDescription)")
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isImporting = false
            guard let firstImage = receivedImages.min(by: { $0.index < $1.index }) else {
                self.statusLabel.text = errors.first ?? "图片接收失败：没有可处理的图片"
                self.retryButton.isHidden = false
                return
            }
            do {
                try SharedImageInbox.save(firstImage.data)
                self.hasSavedImage = true
                self.openContainingApp(errors: errors)
            } catch {
                self.statusLabel.text = "第 \(firstImage.index + 1) 张图片写入 App Group 失败：\(error.localizedDescription)"
                self.retryButton.isHidden = false
            }
        }
    }

    @objc private func retry() {
        if hasSavedImage {
            openContainingApp(errors: [])
        } else {
            importImages()
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func openContainingApp(errors: [String]) {
        let url = URL(string: "wristtrip://import")!
        let attemptID = UUID()
        launchAttemptID = attemptID
        isLaunchPending = true
        retryButton.isHidden = true
        doneButton.isHidden = true
        statusLabel.text = "图片已接收，正在打开腕上车次…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard self?.launchAttemptID == attemptID else { return }
            self?.launchDidFail("打开请求超时，系统没有返回结果", errors: errors)
        }

        // Share extensions have no shared UIApplication; on systems that expose it in
        // the responder chain, opening the registered URL activates the containing app.
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] opened in
                    guard let self, self.launchAttemptID == attemptID, self.isLaunchPending else { return }
                    if opened {
                        self.isLaunchPending = false
                        self.extensionContext?.completeRequest(returningItems: nil)
                    } else {
                        self.openThroughExtensionContext(url, attemptID: attemptID, errors: errors,
                                                         priorFailure: "UIKit 拒绝打开 wristtrip://import")
                    }
                }
                return
            }
            responder = current.next
        }
        openThroughExtensionContext(url, attemptID: attemptID, errors: errors,
                                    priorFailure: "扩展响应链中没有应用对象")
    }

    private func openThroughExtensionContext(_ url: URL, attemptID: UUID, errors: [String],
                                             priorFailure: String) {
        guard let context = extensionContext else {
            if launchAttemptID == attemptID {
                launchDidFail("\(priorFailure)；分享扩展上下文不可用", errors: errors)
            }
            return
        }
        context.open(url) { [weak self] opened in
            DispatchQueue.main.async {
                guard let self, self.launchAttemptID == attemptID, self.isLaunchPending else { return }
                if opened {
                    self.isLaunchPending = false
                    context.completeRequest(returningItems: nil)
                } else {
                    self.launchDidFail("\(priorFailure)；系统不允许此分享扩展打开 wristtrip://import",
                                       errors: errors)
                }
            }
        }
    }

    private func launchDidFail(_ reason: String, errors: [String]) {
        guard isLaunchPending else { return }
        isLaunchPending = false
        statusLabel.text = ["主 App 唤起失败：\(reason)。图片已暂存，主 App 下次打开时可继续导入。",
                            errors.first.map { "部分图片接收失败：\($0)" }]
            .compactMap { $0 }.joined(separator: "；")
        retryButton.setTitle("重试打开", for: .normal)
        retryButton.isHidden = false
        doneButton.isHidden = false
    }

    private struct ImageReceptionError: LocalizedError {
        let types: [String]
        let attempts: [String]

        var errorDescription: String? {
            let typeText = types.isEmpty ? "未声明图片类型" : types.joined(separator: ", ")
            return "无法读取系统提供的图片（类型：\(typeText)；\(attempts.suffix(4).joined(separator: "；"))）"
        }
    }

    private static func loadImageData(from provider: NSItemProvider,
                                      completion: @escaping (Result<Data, Error>) -> Void) {
        func priority(_ identifier: String) -> Int {
            guard let type = UTType(identifier) else { return 4 }
            if type.conforms(to: .image) { return identifier == UTType.image.identifier ? 1 : 0 }
            if type.conforms(to: .fileURL) { return 2 }
            return 3
        }
        let types = provider.registeredTypeIdentifiers
            .filter {
                guard let type = UTType($0) else { return false }
                return type.conforms(to: .image) || type.conforms(to: .data) || type.conforms(to: .fileURL)
            }
            .sorted { priority($0) < priority($1) }
        var attempts: [String] = []

        func usable(_ data: Data?) -> Data? {
            guard let data, UIImage(data: data) != nil else { return nil }
            return data
        }

        func fileData(at url: URL) throws -> Data {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }

        func tryType(at index: Int) {
            guard index < types.count else {
                completion(.failure(ImageReceptionError(types: provider.registeredTypeIdentifiers,
                                                        attempts: attempts)))
                return
            }
            let type = types[index]
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data = usable(data) {
                    completion(.success(data))
                    return
                }
                attempts.append("\(type) 数据：\(error?.localizedDescription ?? "无法解码（\(data?.count ?? 0) 字节）")")

                provider.loadFileRepresentation(forTypeIdentifier: type) { fileURL, fileError in
                    if let fileURL {
                        do {
                            if let data = usable(try fileData(at: fileURL)) {
                                completion(.success(data))
                                return
                            }
                            attempts.append("\(type) 文件：内容无法解码")
                        } catch {
                            attempts.append("\(type) 文件：\(error.localizedDescription)")
                        }
                    } else {
                        attempts.append("\(type) 文件：\(fileError?.localizedDescription ?? "未提供文件")")
                    }

                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, itemError in
                        do {
                            let data: Data?
                            if let image = item as? UIImage {
                                data = image.pngData()
                            } else if let fileURL = item as? URL {
                                data = try fileData(at: fileURL)
                            } else {
                                data = item as? Data
                            }
                            if let data = usable(data) {
                                completion(.success(data))
                                return
                            }
                            attempts.append("\(type) 对象：\(itemError?.localizedDescription ?? "不是可解码的图片")")
                        } catch {
                            attempts.append("\(type) 对象：\(error.localizedDescription)")
                        }
                        tryType(at: index + 1)
                    }
                }
            }
        }

        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage, let data = usable(image.pngData()) {
                    completion(.success(data))
                } else {
                    attempts.append("UIImage 对象：\(error?.localizedDescription ?? "无法转换为图片数据")")
                    tryType(at: 0)
                }
            }
        } else {
            tryType(at: 0)
        }
    }

}
