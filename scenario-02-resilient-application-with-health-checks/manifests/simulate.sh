#!/usr/bin/env sh
# Resilient application simulation script for Kubernetes health checks
# This script simulates realistic application behavior including:
# - Startup delays
# - Occasional liveness failures (to demonstrate pod restarts)
# - Occasional readiness failures (to demonstrate traffic routing)

# Exit immediately if a command exits with a non-zero status
# Print commands before execution
# Treat unset variables as an error
set -eux

# Configurable parameters (set as environment variables or use defaults)
: "${STARTUP_DELAY_SEC:=5}"
: "${FAILURE_RATE:=0.3}"
: "${LIVENESS_FAILURE_DURATION:=20}"       # How long to fail liveness checks (seconds)
: "${READINESS_FAILURE_DURATION:=15}"      # How long to fail readiness checks (seconds)
: "${READINESS_FAILURE_RATE:=0.15}"        # Probability of readiness failures
: "${SIMULATE_RESOURCE_EXHAUSTION:=false}" # Whether to simulate CPU/memory exhaustion

WEB_ROOT="/usr/share/nginx/html"
HEALTH_PATH="${WEB_ROOT}/health"
READY_PATH="${WEB_ROOT}/ready"
STARTUP_PATH="${WEB_ROOT}/startup"

# Trap to handle cleanup on script termination
cleanup() {
  echo "Cleaning up and exiting..."
  # Kill any background processes we've started
  jobs -p | xargs -r kill
  exit 0
}
trap cleanup SIGTERM SIGINT

# Create web directories
echo "Initializing web directories..."
mkdir -p "${HEALTH_PATH}" "${READY_PATH}" "${STARTUP_PATH}"

# Create a custom 503 error page
cat > "${WEB_ROOT}/503.html" << 'EOL'
<!DOCTYPE html>
<html>
<head>
  <title>Service Temporarily Unavailable</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 50px; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 5px; }
    h1 { color: #d9534f; }
    .timestamp { color: #666; font-size: 0.8em; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Service Temporarily Unavailable</h1>
    <p>The service is currently experiencing a simulated failure for demonstration purposes.</p>
    <p>This page indicates that the service has detected a problem and is properly reporting its unavailability.</p>
    <p class="timestamp">Generated at: <span id="timestamp"></span></p>
  </div>
  <script>
    document.getElementById('timestamp').textContent = new Date().toISOString();
  </script>
</body>
</html>
EOL

# 1) Simulate application startup process
echo "Simulating application startup process (${STARTUP_DELAY_SEC}s)..."
sleep "${STARTUP_DELAY_SEC}"

# Initialize health endpoints
echo "OK" > "${HEALTH_PATH}/index.html"
echo "OK" > "${READY_PATH}/index.html"

# Record startup time
START_TIME=$(date +%s)
echo "Application started at: $(date)"
echo "OK" > "${STARTUP_PATH}/index.html"

# 2) Function to simulate liveness failures
simulate_liveness_failure() {
  echo "$(date) [FAILURE] Simulating liveness probe failure..."
  # Remove the file to cause 404
  rm -f "${HEALTH_PATH}/index.html"

  sleep "${LIVENESS_FAILURE_DURATION}"

  # If container hasn't been restarted by now, restore health
  if [ -d "${HEALTH_PATH}" ]; then
    echo "$(date) [RECOVERY] Restoring liveness endpoint..."
    echo "OK" > "${HEALTH_PATH}/index.html"
  fi
}

# 3) Function to simulate readiness failures (service remains alive but not ready for traffic)
simulate_readiness_failure() {
  echo "$(date) [DEGRADED] Simulating readiness probe failure..."
  # Remove the file to cause 404
  rm -f "${READY_PATH}/index.html"

  sleep "${READINESS_FAILURE_DURATION}"

  echo "$(date) [RESTORED] Restoring readiness endpoint..."
  echo "OK" > "${READY_PATH}/index.html"
}

# 4) Function to simulate high CPU usage
simulate_cpu_load() {
  echo "$(date) [RESOURCE] Simulating high CPU usage for 10 seconds..."
  # Create CPU load with a calculation loop
  for i in $(seq 1 2); do
    # Start a background process that creates CPU load
    (
      end=$((SECONDS+5))
      while [ $SECONDS -lt $end ]; do
        # Heavy math calculation to create CPU load
        for j in $(seq 1 10000); do
          echo "scale=10; s($j) * c($j)" | bc -l >/dev/null 2>&1
        done
      done
    ) &
  done
  sleep 10
  echo "$(date) [RESOURCE] CPU load simulation completed"
}

# 5) Start failure simulation loop in background
(
  # Give the container time to stabilize before starting failure simulations
  sleep 30

  while true; do
    # Calculate uptime
    CURRENT_TIME=$(date +%s)
    UPTIME=$((CURRENT_TIME - START_TIME))

    echo "Current uptime: ${UPTIME}s, FAILURE_RATE=${FAILURE_RATE}"

    # Simulate liveness failure based on probability
    if [ "${FAILURE_RATE}" != "0" ]; then
      RAND_LIVENESS=$(awk "BEGIN{printf \"%.2f\", ${RANDOM}/32767}")
      if [ "$(echo "${RAND_LIVENESS} < ${FAILURE_RATE}" | bc -l)" -eq 1 ]; then
        simulate_liveness_failure
      fi
    fi

    # Sleep between checks to prevent too frequent failures
    sleep 20

    # Simulate readiness failures (separate from liveness)
    if [ "${READINESS_FAILURE_RATE}" != "0" ]; then
      RAND_READINESS=$(awk "BEGIN{printf \"%.2f\", ${RANDOM}/32767}")
      if [ "$(echo "${RAND_READINESS} < ${READINESS_FAILURE_RATE}" | bc -l)" -eq 1 ]; then
        simulate_readiness_failure
      fi
    fi

    # Optionally simulate CPU load (if enabled)
    if [ "${SIMULATE_RESOURCE_EXHAUSTION}" = "true" ]; then
      RAND_RESOURCE=$(awk "BEGIN{printf \"%.2f\", ${RANDOM}/32767}")
      if [ "$(echo "${RAND_RESOURCE} < 0.1" | bc -l)" -eq 1 ]; then
        simulate_cpu_load
      fi
    fi

    # Sleep between simulations to prevent too frequent failures
    sleep 40
  done
) &

# 6) Start nginx in the foreground
echo "Starting nginx..."
exec nginx -g 'daemon off;'