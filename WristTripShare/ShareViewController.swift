import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var providers: [NSItemProvider] = []
    private var isImporting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { provider in
                provider.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: .image) == true }
            }

        statusLabel.text = providers.isEmpty ? "未收到图片。请从 12306 分享订单图片。" : "收到 \(providers.count) 张图片"
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        actionButton.setTitle("保存到抬腕车次", for: .normal)
        actionButton.isEnabled = !providers.isEmpty
        actionButton.addTarget(self, action: #selector(importImages), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, actionButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc private func importImages() {
        guard !isImporting else { return }
        isImporting = true
        actionButton.isEnabled = false
        statusLabel.text = "正在保存图片…"

        let group = DispatchGroup()
        let lock = NSLock()
        var saved = 0
        for provider in providers {
            guard let type = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) else { continue }
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                defer { group.leave() }
                guard let data, UIImage(data: data) != nil else { return }
                guard (try? SharedImageInbox.save(data)) != nil else { return }
                lock.lock()
                saved += 1
                lock.unlock()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isImporting = false
            if saved > 0 {
                self.statusLabel.text = "已保存 \(saved) 张图片。打开抬腕车次核对车票。"
                self.actionButton.setTitle("完成", for: .normal)
                self.actionButton.removeTarget(self, action: #selector(self.importImages), for: .touchUpInside)
                self.actionButton.addTarget(self, action: #selector(self.finish), for: .touchUpInside)
            } else {
                self.statusLabel.text = "图片保存失败，请重试或在 App 中从相册导入。"
            }
            self.actionButton.isEnabled = true
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
