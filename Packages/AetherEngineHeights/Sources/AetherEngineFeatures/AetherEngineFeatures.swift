@_exported import AetherEngine

/// The optional components this build has, as the engine reports them at run time.
public let enabledOptionalComponents = AetherEngine.OptionalComponent.allCases.filter(\.isBuiltIn)
