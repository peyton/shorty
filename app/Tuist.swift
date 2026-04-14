import ProjectDescription

let tuist = Tuist(
    fullHandle: "peyton/shorty",
    cache: .cache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            includeGenerateScheme: false,
            enableCaching: true,
            registryEnabled: true
        )
    )
)
