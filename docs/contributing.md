# Contributing

See [CONTRIBUTING.md](https://github.com/pmady/keda-gpu-scaler/blob/main/CONTRIBUTING.md) for the full guide.

## Quick version

1. Fork and clone
2. `make test` to run unit tests (no GPU needed)
3. `make lint` for golangci-lint
4. Commit with sign-off: `git commit -s -m "feat: my change"`
5. Open a PR

Build requires `CGO_ENABLED=1` for the NVML bindings. Tests and lint work without a GPU.
