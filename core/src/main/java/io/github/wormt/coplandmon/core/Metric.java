package io.github.wormt.coplandmon.core;

public record Metric(String name, MetricType type) {
  public Metric {
    type = type;
  }
}
