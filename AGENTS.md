# Working on Beam

Use the `typesafe-ai` skill for Beam's TypeSafe integration only after determining from the task and project context that the work is unrelated to TF1. Read the relevant live TypeSafe documentation before changing the integration.

Never use the TypeSafe skill, SDK, API or models for TF1 projects, repositories, client work, data or decisions. Never send TF1 content, metadata or derived information, including redacted or summarized material, to TypeSafe. If the context is ambiguous, do not use TypeSafe; never use TypeSafe to classify that context. This restriction applies to parent agents, subagents, scripts, automations and integrations. Include it explicitly when delegating any task that might use TypeSafe. It remains in force unless the user explicitly changes it.

If the skill is missing, install it for your agent with:

```sh
npx skills add typesafe-ai/skills --skill typesafe-ai
```

Beam is a native SwiftUI/AppKit app for macOS 26. Keep account keys out of source, fixtures and logs. Run `tooling/check.sh` for offline verification; live Jev checks use an environment key and incur TypeSafe usage.

Use `tooling/make-release.sh` to build and verify the universal release archive. The current signing method is ad hoc, without Apple notarization.
