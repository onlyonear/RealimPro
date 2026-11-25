import SwiftUI
import UniformTypeIdentifiers

// MARK: - 系统文件选择器（SwiftUI 桥接）
struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    // 系统物化（iCloud 下载/复制进容器）失败、回调返回空数组时触发，避免界面静默无反应
    var onError: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // .musicxml 没有系统内置 UTType，按扩展名声明；.xml 同时纳入（导入时再嗅探 <score-partwise>）
        let musicXMLType = UTType(filenameExtension: "musicxml") ?? UTType.xml
        let types: [UTType] = [.plainText, .html, .json, .xml, musicXMLType]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    // MARK: - Coordinator
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onError: (() -> Void)?

        init(onPick: @escaping (URL) -> Void, onError: (() -> Void)?) {
            self.onPick = onPick
            self.onError = onError
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // 空数组 = 文件未能在磁盘物化（常见于 iCloud 占位符未下载），明确报错而非静默返回
            guard let url = urls.first else {
                onError?()
                return
            }
            onPick(url)
        }
    }
}
