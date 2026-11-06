import Foundation

/// 调试日志输出封装
///
/// 在 DEBUG 构建中调用标准 `print`，在 Release 构建中为空实现，
/// 避免调试日志影响上架版本的性能。
///
/// 用法：将所有调试用的 `print(...)` 替换为 `dprint(...)`
func dprint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    print(items, separator: separator, terminator: terminator)
    #endif
}
