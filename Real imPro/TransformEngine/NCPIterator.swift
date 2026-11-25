import Foundation

// 直接扩展全局已存在的 TransformEngine，不再重复声明 enum TransformEngine
extension TransformEngine {
    /// 对标原版 NCPIterator，迭代遍历 NoteChordPair 数组
    struct NCPIterator {
        private let sequence: [NoteChordPair]
        private var currentIndex: Int
        
        /// 初始化，绑定需要遍历的旋律序列
        init(sequence: [NoteChordPair]) {
            self.sequence = sequence
            self.currentIndex = 0
        }
        
        /// 是否还有下一个元素
        func hasNext() -> Bool {
            currentIndex < sequence.count
        }
        
        /// 获取下一个 NCP，同时步进索引
        mutating func nextNCP() -> NoteChordPair? {
            guard hasNext() else { return nil }
            let item = sequence[currentIndex]
            currentIndex += 1
            return item
        }
        
        /// 查看当前位置元素，不移动指针（预览）
        func peek() -> NoteChordPair? {
            guard hasNext() else { return nil }
            return sequence[currentIndex]
        }
        
        /// 重置迭代器回到起始位置
        mutating func reset() {
            currentIndex = 0
        }
        
        /// 跳过指定数量音符
        mutating func skip(count: Int) {
            currentIndex += count
            if currentIndex < 0 { currentIndex = 0 }
            if currentIndex > sequence.count { currentIndex = sequence.count }
        }
    }
}
