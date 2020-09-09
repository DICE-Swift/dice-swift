//
//  DIContainer.swift
//  DICE
//
//  Created by Alexander Tereshkov on 7/9/20.
//

import Foundation

public final class DIContainer: CustomStringConvertible {
    
    lazy var resolveStorage: [ObjectIdentifier: Any] = [:]
    private(set) var containerStorage = DIContainerStorage()
    
    lazy var resolveObjectGraphStorage: [ObjectIdentifier: Any] = [:]
    var objectGraphStackDepth: Int = 0
    
    public var description: String {
        return containerStorage.storedObjects.description
    }
    
    public init() {
        
    }
    
}

// MARK: API

extension DIContainer {
    
    @discardableResult
    public func register<T>(_ type: T.Type = T.self, scope: DIScope? = nil, _ closure: @escaping (DIContainer) -> T) -> DIContainerBuilder<T> {
        let scope = scope ?? DICE.Defaults.scope
        
        let initer = LazyObject(initBlock: closure, container: self)
        let object = DIObject(lazy: initer, type: type, scope: scope)
        
        // Add singleton objects to instantiate objects right away before building to make it accessible right after injection and resolving nested dependencies
        // Aslo avoids race condition reported in https://github.com/DICE-Swift/dice/issues/8
        if object.scope == .single {
            let resolvedObject = closure(self) as Any
            resolveStorage[ObjectIdentifier(type)] = resolvedObject
            return DIContainerBuilder(container: self, object: object)
        }
        
        return DIContainerBuilder(container: self, object: object)
    }
    
    public func resolve<T>(bundle: Bundle? = nil) -> T {
        if let object = makeObject(for: T.self, bundle: bundle) {
            return object as! T
        } else {
            fatalError("Couldn't found object for type \(T.self)")
        }
    }
    
}

// MARK: - Private

private extension DIContainer {
    
    func makeObject(for type: Any.Type, bundle: Bundle?, usingObject: DIObject? = nil) -> Any? {
        let object = usingObject ?? findObject(for: type, bundle: bundle)
        let key = ObjectIdentifier(object.type)
        
        switch object.scope {
        case .single:
            return resolveStorage[key]
        case .prototype:
            return object.lazy.resolve()
        case .weak:
            if let weakReference = resolveStorage[key] as? WeakObject<AnyObject> {
                return weakReference.value
            }
            
            let resolvedObject = object.lazy.resolve() as AnyObject
            let weakObject = WeakObject(value: resolvedObject)
            resolveStorage[key] = weakObject
            return resolvedObject
        case .objectGraph:
            defer { objectGraphStackDepth -= 1 }
            
            if let object = resolveObjectGraphStorage[key] {
                if objectGraphStackDepth == 0 {
                    resolveObjectGraphStorage.removeAll()
                }
                return object
            }
            
            objectGraphStackDepth += 1
            let value = object.lazy.resolve() as Any
            resolveObjectGraphStorage[key] = value
            
            let mirror = Mirror(reflecting: value)
            
            for child in mirror.children {
                if let injectable = child.value as? InjectableProperty {
                    let subject = findObject(for: injectable.type, bundle: injectable.bundle)
                    if subject.scope != .single && subject.scope != .weak {
                        objectGraphStackDepth += 1
                        resolveObjectGraphStorage[ObjectIdentifier(subject.type)] = self.makeObject(for: subject.type, bundle: subject.bundle, usingObject: subject)
                    }
                }
            }
            
            return value
        }
    }
    
    func findObject(for type: Any.Type, bundle: Bundle?) -> DIObject {
        guard let object = containerStorage[type] else {
            fatalError("Can't found object for type \(type)")
        }
        
        if let bundle = bundle {
            if object.bundle != bundle {
                fatalError("Can't resolve object from passed bundle. Bundles are not equal")
            }
        }
        
        return object
    }
    
}
