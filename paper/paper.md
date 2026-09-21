---
title: 'keda-gpu-scaler: GPU-aware autoscaling for Kubernetes from real hardware metrics'
tags:
  - Kubernetes
  - GPU
  - autoscaling
  - KEDA
  - NVML
  - Go
  - machine learning inference
authors:
  - name: Pavan Madduri
    orcid: 0009-0007-3795-7593
    affiliation: 1
affiliations:
  - name: Independent Researcher, USA
    index: 1
date: 20 September 2026
bibliography: paper.bib
---

# Summary

`keda-gpu-scaler` is a Kubernetes External Scaler for KEDA [@keda] that drives
horizontal autoscaling of GPU workloads from GPU hardware metrics. It runs as a
DaemonSet on GPU nodes, reads per-device state directly from the NVIDIA
Management Library (NVML) [@nvml], and serves those metrics to KEDA over the
external scaler gRPC contract. Workloads can then scale on GPU utilization,
memory use, or engine-level signals, including scaling to and from zero
replicas. Beyond raw device metrics, the scaler can read serving-engine signals
such as vLLM [@kwon2023vllm] queue depth and NVIDIA Triton queue statistics, so
scaling can track request pressure rather than only device saturation. It
supports Multi-Instance GPU (MIG) partitions and several aggregation strategies
(max, min, average, sum, and percentiles) for nodes with multiple GPUs.

# Statement of need

The Kubernetes Horizontal Pod Autoscaler reacts to CPU and memory, neither of
which reflects GPU saturation. A GPU inference pod can sit at single-digit CPU
utilization while its GPU is fully saturated, so CPU- and memory-based
autoscaling either over-provisions or fails to respond. The common workaround
chains `dcgm-exporter` into Prometheus, evaluates PromQL, and feeds the result
back through KEDA. That pipeline adds several moving parts and tens of seconds of
metric latency, which is significant when GPU capacity is expensive and demand is
bursty.

`keda-gpu-scaler` removes that pipeline. Because it reads NVML on the node and
answers KEDA directly, scaling decisions are based on live hardware state without
an intermediate metrics store or query language. This matters for large language
model serving and other GPU inference workloads, where operators need to scale
on GPU utilization or on serving-engine backpressure, and where scale-to-zero
meaningfully reduces cost. The project targets platform and machine learning
infrastructure engineers who run GPU workloads on Kubernetes and want autoscaling
that reflects what the accelerator is actually doing.

# Functionality

The scaler exposes the four methods of the KEDA external scaler interface and is
configured entirely through standard `ScaledObject` trigger metadata. Key
capabilities include:

- Per-device metrics from NVML: utilization, memory used and total, temperature,
  and power draw.
- Serving-engine metrics: vLLM pending queue depth and KV-cache usage, and
  Triton queue statistics, for request-aware scaling.
- Multi-GPU aggregation strategies (`max`, `min`, `avg`, `sum`, `p95`, `p99`).
- MIG per-instance metrics for partitioned GPUs.
- Scale-to-zero and configurable cooldown to prevent scale-down flapping.
- An optional Prometheus endpoint for fleet monitoring, independent of the
  scaling path.

The design and rationale, including why GPU support is implemented as a
standalone external scaler rather than embedded in KEDA core, are documented in
the repository.

# Acknowledgements

The project builds on the KEDA project [@keda], the NVIDIA Management Library
[@nvml], and the broader Kubernetes ecosystem [@burns2016borg].

# References
