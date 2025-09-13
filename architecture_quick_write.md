# WIP - Architecture Quick Write

**The Frontend: Parsing and Linkage**
The frontend for the caffeine compiler consists of a directory of yaml files split between two types:
1. **specifications:** these define the services, sli types, and sli filters accessible for instantiation
2. **instantiations:** these define the SLOs to be generated, split by team and service.

The directory structure is prescriptive and follows the following pattern:
```
├── foobar_team
│   ├── authentication.yaml
│   └── database.yaml
└── bar_team
|    └── authentication.yaml
├── specifications
|    ├── services.yaml
|    ├── sli_types.yaml
|    └── sli_filters.yaml
```

To summarize, there is a single subdirectory for specifications with all service definitions, sli types, and sli filters living within a single `.yaml` file. Instantiations are split by team and service, with each team containing a directory of services, each with its own `.yaml` file defining the SLOs to be generated. These instantiations are defined according to the specifications.

Thus, the first step of compilation is to parse the specifications and translate them into an intermediate representation language (IR); each file is parsed and translated to the IR as completely as possible, some fields aren't fully sugared until the following linkage step.

Once the files are parsed and the IR is generated, sugared, and linked, we have a single `organization` structure containing both the specifications and instantiations.

**The Next Step: Type Checking and Semantic Analysis**
The next step is to traverse the IR and perform type checking and semantic analysis: here we check a whole host of things such as ensuring that the sli filters are properly typed, that only valid sli types are used per service, slo thresholds are sane, etc. As the compiler evolves, we expect to add more and more checks here to aid the user in writing valid and meaningful SLOs.

**The Final Step: Reliability Artifact Generation**
The final step is to generate the desired artifacts from the IR. Today this is simply Datadog SLOs and a dashboard, but we expect to add more and more artifacts in the future.

**A Design of Maximum Modularity**
Unlike the initial design of the compiler, here we've done a proper job of isolating each phase. This enables a level of extensibility that we've never had before. For example, if we want to support a different DSL as the frontend, add a new type of reliability artifact, or extend the semantic analyzer, as long as each phase maintains its interface boundaries, we can do so without breaking the compiler.
