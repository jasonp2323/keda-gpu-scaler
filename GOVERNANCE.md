# Governance

This document describes the governance model for keda-gpu-scaler.

## Overview

keda-gpu-scaler is currently a single-maintainer project. As the project grows and attracts contributors, governance will evolve to reflect the broader community. The goal is to keep things lightweight and transparent while the project is small, and formalize roles as participation increases.

## Roles

### Maintainer

Maintainers have full commit access and are responsible for:

- Reviewing and merging pull requests
- Triaging issues
- Cutting releases
- Setting project direction and roadmap
- Enforcing the Code of Conduct

Current maintainers:

| Name | GitHub | Role |
|------|--------|------|
| Pavan Madduri | [@pmady](https://github.com/pmady) | Project creator, lead maintainer |

### Contributor

Anyone who has had a pull request merged. Contributors are listed in the GitHub contributors graph and recognized in release notes when applicable.

### Reviewer

As the contributor base grows, active contributors may be granted reviewer status, which means their approvals count toward the review requirement on pull requests. Reviewers are nominated by maintainers based on sustained, quality contributions.

## Decision Making

- Day-to-day decisions (bug fixes, minor features, dependency updates) are made by the maintainer through the normal PR review process.
- Larger decisions (new scaling profiles, architecture changes, breaking API changes) are discussed in a GitHub issue or discussion before implementation. Anyone can participate.
- If there is disagreement, the maintainer makes the final call, with reasoning documented in the relevant issue.

## Adding Maintainers

New maintainers may be added when:

1. They have a sustained track record of quality contributions (code, reviews, docs, or community support)
2. They demonstrate good judgment about project direction
3. An existing maintainer nominates them
4. There are no objections from other maintainers after a 7-day comment period on a governance issue

## Releases

Releases follow [semantic versioning](https://semver.org/). Any maintainer can cut a release. Release notes are generated from the changelog and published as GitHub Releases.

## Changes to Governance

Changes to this document are proposed via pull request and require approval from at least one maintainer. Significant governance changes (e.g., adding a steering committee) will be discussed in a GitHub issue first.

## Code of Conduct

This project follows the [CNCF Code of Conduct](https://github.com/cncf/foundation/blob/main/code-of-conduct.md). See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
