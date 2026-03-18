# policy-platform

PolicyHub — git-backed policy management platform.

This repository will contain the PolicyHub application source code.

## Documentation

All specification documents are in [`docs/specification/`](docs/specification/).

| Document | Description |
|----------|-------------|
| [README.md](docs/specification/README.md) | Developer setup guide, commands, project structure |
| [docker-compose.yml](docs/specification/docker-compose.yml) | Reference local service configuration (Postgres, Valkey, Typesense) |
| [.env.example](docs/specification/.env.example) | Reference environment variable reference |
| [docker/postgres/init.sql](docs/specification/docker/postgres/init.sql) | Postgres initialisation script (enables pgvector) |
| [policy-platform-architecture.md](docs/specification/policy-platform-architecture.md) | Architecture & technology stack |
| [policy-platform-licensing.md](docs/specification/policy-platform-licensing.md) | Dependency licence analysis |
| [policy-platform-implementation-flow.md](docs/specification/policy-platform-implementation-flow.md) | 5-milestone implementation plan |
| [policy-platform-schema-api.md](docs/specification/policy-platform-schema-api.md) | Database schema & API route reference |
| [policy-platform-project-structure.md](docs/specification/policy-platform-project-structure.md) | AdonisJS v7 project structure & conventions |
| [PolicyHub_ADRs.docx](docs/specification/PolicyHub_ADRs.docx) | Architecture Decision Records (10 ADRs) |
| [PolicyHub_Sprints.docx](docs/specification/PolicyHub_Sprints.docx) | Sprint breakdown — stories & acceptance criteria |
| [PolicyHub_GitLab_Setup.docx](docs/specification/PolicyHub_GitLab_Setup.docx) | GitLab content repository setup guide |
| [PolicyHub_Entra_Setup.docx](docs/specification/PolicyHub_Entra_Setup.docx) | Microsoft Entra ID app registration guide |
| [PolicyHub_UX_Spec.pdf](docs/specification/PolicyHub_UX_Spec.pdf) | UX specification — authoring & reader surfaces (screens 01–08) |
| [PolicyHub_Admin_UX_Spec.pdf](docs/specification/PolicyHub_Admin_UX_Spec.pdf) | UX specification — admin surface (screens 09–14) |
| [reader_screens.html](docs/specification/reader_screens.html) | Interactive reader screen wireframes |
| [admin_screens.html](docs/specification/admin_screens.html) | Interactive admin screen wireframes |

> These documents are illustrative specifications produced during the design phase.
> The development team is free to adapt any of them as the project evolves.
