/*
Copyright 2026 The keda-gpu-scaler Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package gpu

import (
	"testing"
)

var twoGPUs = []Metrics{
	{
		Index:              0,
		UUID:               "GPU-aaaa-1111",
		Name:               "NVIDIA A100-SXM4-80GB",
		GPUUtilization:     85,
		MemoryUtilization:  70,
		MemoryUsedMiB:      57344,
		MemoryTotalMiB:     81920,
		TemperatureCelsius: 72,
		PowerDrawWatts:     300,
		PowerLimitWatts:    400,
	},
	{
		Index:              1,
		UUID:               "GPU-bbbb-2222",
		Name:               "NVIDIA A100-SXM4-80GB",
		GPUUtilization:     20,
		MemoryUtilization:  15,
		MemoryUsedMiB:      12288,
		MemoryTotalMiB:     81920,
		TemperatureCelsius: 38,
		PowerDrawWatts:     75,
		PowerLimitWatts:    400,
	},
}

func TestMockCollectorCollectAll(t *testing.T) {
	c := NewMockCollector(twoGPUs)
	got, err := c.CollectAll()
	if err != nil {
		t.Fatalf("CollectAll() error = %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("CollectAll() returned %d devices, want 2", len(got))
	}
	if got[0].UUID != "GPU-aaaa-1111" {
		t.Errorf("device 0 UUID = %v, want GPU-aaaa-1111", got[0].UUID)
	}
	if got[1].GPUUtilization != 20 {
		t.Errorf("device 1 GPUUtilization = %v, want 20", got[1].GPUUtilization)
	}
}

func TestMockCollectorCollectDevice(t *testing.T) {
	c := NewMockCollector(twoGPUs)

	tests := []struct {
		name     string
		index    int
		wantErr  bool
		wantUUID string
	}{
		{"valid index 0", 0, false, "GPU-aaaa-1111"},
		{"valid index 1", 1, false, "GPU-bbbb-2222"},
		{"negative index", -1, true, ""},
		{"index out of range", 5, true, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := c.CollectDevice(tt.index)
			if (err != nil) != tt.wantErr {
				t.Errorf("CollectDevice(%d) error = %v, wantErr %v", tt.index, err, tt.wantErr)
				return
			}
			if !tt.wantErr && got.UUID != tt.wantUUID {
				t.Errorf("CollectDevice(%d) UUID = %v, want %v", tt.index, got.UUID, tt.wantUUID)
			}
		})
	}
}

func TestMockCollectorDeviceCount(t *testing.T) {
	tests := []struct {
		name    string
		devices []Metrics
		want    int
	}{
		{"two devices", twoGPUs, 2},
		{"no devices", []Metrics{}, 0},
		{"single device", twoGPUs[:1], 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := NewMockCollector(tt.devices)
			got, err := c.DeviceCount()
			if err != nil {
				t.Fatalf("DeviceCount() error = %v", err)
			}
			if got != tt.want {
				t.Errorf("DeviceCount() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestMockCollectorClose(t *testing.T) {
	c := NewMockCollector(twoGPUs)
	if err := c.Close(); err != nil {
		t.Errorf("Close() error = %v", err)
	}
}

func TestMockCollectorImplementsInterface(t *testing.T) {
	// compile-time check that MockCollector satisfies MetricsCollector
	var _ MetricsCollector = (*MockCollector)(nil)
}

func TestMetricsFields(t *testing.T) {
	m := Metrics{
		Index:              0,
		UUID:               "GPU-test",
		Name:               "NVIDIA H100",
		GPUUtilization:     95,
		MemoryUtilization:  88,
		MemoryUsedMiB:      65536,
		MemoryTotalMiB:     81920,
		TemperatureCelsius: 80,
		PowerDrawWatts:     650,
		PowerLimitWatts:    700,
	}

	if m.GPUUtilization != 95 {
		t.Errorf("GPUUtilization = %v, want 95", m.GPUUtilization)
	}
	if m.MemoryUsedMiB != 65536 {
		t.Errorf("MemoryUsedMiB = %v, want 65536", m.MemoryUsedMiB)
	}
	if m.PowerDrawWatts > m.PowerLimitWatts {
		t.Error("PowerDrawWatts should not exceed PowerLimitWatts in normal operation")
	}
}

func TestCollectAllEmptyDevices(t *testing.T) {
	c := NewMockCollector([]Metrics{})
	got, err := c.CollectAll()
	if err != nil {
		t.Fatalf("CollectAll() error = %v", err)
	}
	if len(got) != 0 {
		t.Errorf("CollectAll() with no devices returned %d, want 0", len(got))
	}
}

func TestCollectDeviceBoundary(t *testing.T) {
	single := []Metrics{twoGPUs[0]}
	c := NewMockCollector(single)

	// index 0 should work
	if _, err := c.CollectDevice(0); err != nil {
		t.Errorf("CollectDevice(0) unexpected error: %v", err)
	}

	// index 1 should fail
	if _, err := c.CollectDevice(1); err == nil {
		t.Error("CollectDevice(1) should fail for single-device collector")
	}
}
