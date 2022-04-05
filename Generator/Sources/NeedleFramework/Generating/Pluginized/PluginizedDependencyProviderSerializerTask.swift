//
//  Copyright (c) 2018. Uber Technologies
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Concurrency
import Foundation
import TSCBasic

/// The task that serializes a list of pluginized processed dependency
/// providers into exportable foramt.
class PluginizedDependencyProviderSerializerTask: AbstractTask<[SerializedProvider]> {

    /// Initializer.
    ///
    /// - parameter providers: The pluginized processed dependency provider
    /// to serialize.
    init(providers: [PluginizedProcessedDependencyProvider]) {
        self.providers = providers
        super.init(id: TaskIds.pluginizedDependencyProviderSerializerTask.rawValue)
    }

    /// Execute the task and returns the in-memory serialized dependency
    /// provider data models.
    ///
    /// - returns: The list of `SerializedProvider`.
    override func execute() -> [SerializedProvider] {
        var result = [SerializedProvider]()
        // Group the providers based on where the properties are coming from
        // This will allow us to extract common code for multiple depndency providers
        // into common base classes
        var counts = OrderedDictionary<[PluginizedProcessedProperty], [PluginizedProcessedDependencyProvider]>()
        for provider in providers {
            let properties = provider.processedProperties
            counts[properties] = (counts[properties] ?? []) + [provider]
        }
        for (baseCount, (_, matchingProviders)) in counts.enumerated() {
            result.append(contentsOf: serialize(matchingProviders, baseCounter: baseCount))
        }
        return result
    }

    // MARK: - Private

    private let providers: [PluginizedProcessedDependencyProvider]

    private func serialize(_ providers: [PluginizedProcessedDependencyProvider], baseCounter: Int) -> [SerializedProvider] {
        var result = [SerializedProvider]()
        let (classNameSerializer, content) = serializedClass(for: providers.first!, counter: baseCounter)
        if providers.first?.data.isEmptyDependency == false {
            result.append(SerializedProvider(content: content, registration: "", attributes: [:]))
        }
        for (_, provider) in providers.enumerated() {
            let paramsSerializer = DependencyProviderParamsSerializer(provider: provider.data)
            let funcNameSerializer = DependencyProviderFuncNameSerializer(classNameSerializer: classNameSerializer, paramsSerializer: paramsSerializer)
            let content = serializedContent(for: provider, classNameSerializer: classNameSerializer, paramsSerializer: paramsSerializer, funcNameSerializer: funcNameSerializer)
            let registration = DependencyProviderRegistrationSerializer(provider: provider.data, factoryFuncNameSerializer: funcNameSerializer).serialize()
            let attributes = calculateAttributes(for: provider.data, funcNameSerializer: funcNameSerializer)
            result.append(SerializedProvider(content: content, registration: registration, attributes: attributes))
        }
        return result
    }

    private func serializedContent(for provider: PluginizedProcessedDependencyProvider, classNameSerializer: Serializer, paramsSerializer: Serializer, funcNameSerializer: Serializer) -> String {
        if provider.data.isEmptyDependency {
            return ""
        }
        return DependencyProviderFuncSerializer(provider: provider.data, funcNameSerializer: funcNameSerializer, classNameSerializer: classNameSerializer, paramsSerializer: paramsSerializer).serialize()
    }

    private func serializedClass(for provider: PluginizedProcessedDependencyProvider, counter: Int) -> (Serializer, String) {
        let classNameSerializer = DependencyProviderClassNameSerializer(provider: provider.data)
        let propertiesSerializer = PluginizedPropertiesSerializer(provider: provider)
        let sourceComponentsSerializer = SourceComponentsSerializer(componentTypes: provider.data.levelMap.keys.sorted())
        let initBodySerializer = DependencyProviderBaseInitSerializer(provider: provider.data)

        let serializer = DependencyProviderClassSerializer(provider: provider.data, classNameSerializer: classNameSerializer, propertiesSerializer: propertiesSerializer, sourceComponentsSerializer: sourceComponentsSerializer, initBodySerializer: initBodySerializer)
        return (classNameSerializer, serializer.serialize())
    }

    private func calculateAttributes(for provider: ProcessedDependencyProvider, funcNameSerializer: Serializer) -> [String: String] {
        if provider.isEmptyDependency {
            return [:]
        }
        var maxLevel: Int = 0
        provider.levelMap.forEach { (componentType: String, level: Int) in
            if level > maxLevel {
                maxLevel = level
            }
        }
        var attributes: [String: String] = [:]
        if maxLevel > 0 {
            attributes["maxLevel"] = String(maxLevel)
        }
        attributes["factoryName"] = funcNameSerializer.serialize()
        return attributes
    }
}
