package io.github.wormt.coplandmon.core;

import java.util.Collections;
import java.util.Map;
import java.util.SortedMap;
import java.util.TreeMap;

public record LabelSet(SortedMap<String, String> labels) {
  public LabelSet {
    labels = Collections.unmodifiableSortedMap(new TreeMap<>(labels));
  }

  public static LabelSet of(Map<String, String> in) {
    return new LabelSet(new TreeMap<>(in));
  }
}
