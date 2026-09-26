import SwiftUI
import UniformTypeIdentifiers

// MARK: - 系统文件选择器（SwiftUI 桥接）
struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
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

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
