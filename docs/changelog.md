# Changelog

See [CHANGELOG.md](https://github.com/pmady/keda-gpu-scaler/blob/main/CHANGELOG.md) for the full release history.

## v0.1.0 (2026-05-19)

Initial release.

- KEDA External Scaler gRPC server implementing `externalscaler.ExternalScalerServer`
- Direct NVML GPU metrics via `go-nvml` C-bindings
- 6 GPU metrics: utilization, memory utilization, memory used (MiB and %), temperature, power draw
- Pre-built profiles: `vllm-inference`, `triton-inference`, `training`, `batch`
- Multi-GPU aggregation: `max`, `min`, `avg`, `sum`
- Scale-to-zero via activation thresholds
- Per-GPU index targeting
- Mock collector for testing without hardware
- DaemonSet manifests and Helm chart
- CI: build, test, lint, Helm lint, Docker push
