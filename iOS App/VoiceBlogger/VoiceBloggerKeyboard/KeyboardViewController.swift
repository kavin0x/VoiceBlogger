import UIKit

/// Custom keyboard extension entry point for system-wide dictation.
/// Full model inference runs in the main app; the keyboard provides quick capture UI
/// and falls back to opening the host app when memory is constrained.
final class KeyboardViewController: UIInputViewController {
    private let dictateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.accessibilityLabel = "Dictate"
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        dictateButton.addTarget(self, action: #selector(dictateTapped), for: .touchUpInside)
        dictateButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dictateButton)
        NSLayoutConstraint.activate([
            dictateButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dictateButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dictateButton.widthAnchor.constraint(equalToConstant: 44),
            dictateButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func dictateTapped() {
        if let url = URL(string: "voiceblogger://intent/start") {
            extensionContext?.open(url, completionHandler: nil)
        }
        textDocumentProxy.insertText("")
        UIPasteboard.general.string = "Open Voice Blogger to finish dictation."
    }
}
