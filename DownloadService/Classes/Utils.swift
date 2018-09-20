//
//  Utils.swift
//  DownloadService
//
//  Created by Сидорова Анна Константиновна on 20.09.2018.
//

import Foundation

final class Weak<T> {
    private weak var rawValue: AnyObject?
    private(set) var value: T? {
        get { return rawValue as! T? }
        set { rawValue = newValue as AnyObject }
    }
    init(_ value: T) {
        self.value = value
    }

    var isValid: Bool {
        return value != nil
    }
}

class WeakDictionary<Key: Hashable, Value> : Collection {

    typealias Storage = Dictionary<Key, Weak<Value>>
    typealias Index = DictionaryIndex<Key, Weak<Value>>

    private var storage: Storage

    var startIndex: Storage.Index { return storage.startIndex }
    var endIndex: Storage.Index { return storage.endIndex }
    func index(after i: Index) -> Index { return storage.index(after: i) }

    init() {
        storage = [:]
    }

    init(dictionary: [Key : Value]) {
        storage = dictionary.mapValues { Weak($0) }
    }

    private init(withStorage storage: [Key: Weak<Value>]) {
        self.storage = storage
        reap()
    }

    subscript(position: Index) -> (Key, Weak<Value>) {
        reap()
        return storage[position]
    }

    subscript(key: Key) -> Value? {
        get {
            reap()
            return storage[key]?.value
        }
        set {
            reap()
            guard let value = newValue else { return }
            storage[key] = Weak(value)
        }
    }

    subscript(bounds: Range<Index>) -> WeakDictionary<Key, Value> {
        return WeakDictionary(withStorage: Storage(uniqueKeysWithValues: storage[bounds.lowerBound ..< bounds.upperBound].map { $0 }))
    }

    func reap() {
        guard storage.filter({ !$0.value.isValid }).count > 0 else { return }
        storage = storage.filter { $0.value.isValid }
    }
}

let logger: Logger = SimpleLogger()
