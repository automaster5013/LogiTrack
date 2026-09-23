#!/bin/bash -eu

cd "$SRC/logitrack/api"
mvn --batch-mode --no-transfer-progress dependency:copy-dependencies \
  -DincludeArtifactIds=jackson-annotations,jackson-core,jackson-databind \
  -DoutputDirectory="$OUT"

javac -cp "$OUT/*:$JAZZER_API_PATH" -d "$OUT" \
  src/main/java/io/logitrack/alert/RouteDeviationCalculator.java \
  "$SRC/logitrack/.clusterfuzzlite/RouteDeviationFuzzer.java"

runtime_classpath=$(find "$OUT" -maxdepth 1 -name '*.jar' -printf '$this_dir/%f:' | sort)
cat > "$OUT/RouteDeviationFuzzer" <<EOF
#!/bin/sh
# LLVMFuzzerTestOneInput is required for ClusterFuzzLite target detection.
this_dir=\$(dirname "\$0")
LD_LIBRARY_PATH="$JVM_LD_LIBRARY_PATH":\$this_dir \
  \$this_dir/jazzer_driver --agent_path=\$this_dir/jazzer_agent_deploy.jar \
  --cp=${runtime_classpath}\$this_dir --target_class=RouteDeviationFuzzer \
  --jvm_args="-Xmx2048m:-Djava.awt.headless=true" \
  \$@
EOF
chmod +x "$OUT/RouteDeviationFuzzer"
