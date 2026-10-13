import java.time.ZoneId;
import java.util.Set;

/**
 * Run this java file via `java --source 11 script/dump_time_zones.java`.
 * `script/dump_time_zones` is a higher level wrapper that delegates to this
 * and applies additional logic.
 */
public class DumpTimeZones {
  public static void main(String[] args) {
    Set<String> availableZones = ZoneId.getAvailableZoneIds();

    availableZones.stream()
      .sorted()
      .forEach(it -> System.out.println(it));
  }
}
