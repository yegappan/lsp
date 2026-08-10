package io.github.wormt.coplandmon.core;

import java.time.Instant;

public record Sample(Instant timestamp, double value) {
  public Sample {}
}
