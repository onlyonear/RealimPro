import Foundation

// MARK: K3 扁平数据模型（Decodable，替代工程外 K1Doc 通用反射）
// 运行时只按索引查表，不做 handle 解析 / Vector 展开。

struct K3Meta: Decodable {
    let file: String
    let corpusType: String
    let schemaVersion: Int
}

struct K3DataPoint: Decodable {
    let rule: String
    let starter: Bool
    let chordList: [String]
}

struct K3Cluster: Decodable {
    let number: Int
    let dataPoints: [Int]
}

struct K3ClusterSet: Decodable {
    let original: Int
    let relatives: [Int]
    let points: [Int]
}

struct K3Outline: Decodable {
    let measures: Int
    let sets: [Int]
}

struct K3Transition: Decodable {
    let state: Int
    let nextStates: [Int]
    let probabilities: [Double]
}

struct K3Corpus: Decodable {
    let meta: K3Meta
    let dataPoints: [K3DataPoint]
    let clusters: [K3Cluster]
    let clusterSets: [K3ClusterSet]
    let outlines: [K3Outline]
    let transitions: [K3Transition]

    static func load(path: String) throws -> K3Corpus {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try load(data: data)
    }

    static func load(data: Data) throws -> K3Corpus {
        try JSONDecoder().decode(K3Corpus.self, from: data)
    }

    /// 从 app Bundle 加载已打包的 K3 资源（工程内入口，替代命令行 path）。
    /// 文件名形如 `<name>.k3.json`。
    static func load(bundleResource name: String, bundle: Bundle = .main) throws -> K3Corpus {
        guard let url = bundle.url(forResource: name, withExtension: "k3.json") else {
            throw FaithfulError.resourceUnavailable(name: name)
        }
        return try load(data: Data(contentsOf: url))
    }
}
