# openclaw.py — OpenClaw WebSocket CLI Client

A lightweight Python script that communicates with an [OpenClaw](https://openclaw.dev) gateway over WebSocket. Designed for use in Jenkins pipelines to send Gerrit events or URLs to an OpenClaw agent and receive the agent's response (e.g. a code review report in Markdown).

---

## Prerequisites

- Python 3.10+
- Install dependencies:

```bash
pip install -r requirements.txt
```

---

## Quick Start

```bash
# Send a Gerrit change URL to the code-review agent
python3 openclaw.py \
  --url 'wss://openclaw-host?token=YOUR_TOKEN' \
  --agent code_review \
  --identity ~/.openclaw/identity.json \
  --no-verify-ssl \
  'https://gerrit.example.com/c/repo/+/12345'
```

---

## First-Time Device Pairing

OpenClaw requires devices connecting remotely to be approved once. The script generates and persists an Ed25519 device identity. On first run with a new identity file, the gateway will queue the device for approval and the script will fail with a `NOT_PAIRED` error. A system administrator must then approve the device:

**Step 1 — Generate and persist the identity** (happens automatically on first run):

```bash
python3 openclaw.py \
  --url 'wss://openclaw-host?token=TOKEN' \
  --agent main \
  --identity ~/.openclaw/identity.json \
  --no-verify-ssl \
  'hello'
# → Fails with NOT_PAIRED (expected); identity.json is created
```

**Step 2 — Approve the device** (run on the OpenClaw server host):

```bash
# List pending pairing requests
./openclaw.sh devices list

# Approve by request ID
./openclaw.sh devices approve <requestId>
```

**Step 3 — Retry** — all subsequent runs with the same `--identity` file will succeed automatically.

---

## Usage

```
usage: openclaw.py [-h] [--url URL] [--token TOKEN] [--agent AGENT]
                   [--stdin] [--identity FILE] [--timeout TIMEOUT]
                   [--no-verify-ssl] [--quiet]
                   [message]

positional arguments:
  message           Message to send to the agent (use --stdin to read from stdin)

options:
  --url URL         WebSocket URL of the OpenClaw gateway, e.g.
                    wss://host?token=TOKEN  (env: OPENCLAW_URL)
  --token TOKEN     Gateway auth token (env: OPENCLAW_TOKEN).
                    Ignored if token is already embedded in --url.
  --agent AGENT     Agent ID to chat with (env: OPENCLAW_AGENT, default: main)
  --stdin           Read message from stdin instead of positional argument
  --identity FILE   Path to a JSON file for persisting the Ed25519 device identity.
                    If omitted a temporary identity is generated per invocation.
                    (env: OPENCLAW_IDENTITY)
  --timeout TIMEOUT Seconds to wait for the agent response (default: 300)
  --no-verify-ssl   Disable SSL certificate verification (useful for self-signed certs)
  --quiet           Suppress streaming output; only print the final response
```

### Environment Variables

| Variable | CLI flag | Description |
|---|---|---|
| `OPENCLAW_URL` | `--url` | Full gateway WebSocket URL incl. token |
| `OPENCLAW_TOKEN` | `--token` | Auth token (appended to URL if not already present) |
| `OPENCLAW_AGENT` | `--agent` | Agent ID (default: `main`) |
| `OPENCLAW_IDENTITY` | `--identity` | Path to identity JSON file |
| `OPENCLAW_TIMEOUT` | `--timeout` | Response timeout in seconds (default: `300`) |

---

## Jenkins Integration

### Gerrit Trigger + Code Review Agent

Below is a minimal `Jenkinsfile` example. It listens for Gerrit events and sends the raw event JSON to the `code_review` agent.

```groovy
pipeline {
  agent any
  triggers {
    gerrit(
      serverName: 'my-gerrit',
      triggerOnEvents: [patchsetCreated()]
    )
  }
  environment {
    OPENCLAW_URL      = 'wss://openclaw-host?token=YOUR_TOKEN'
    OPENCLAW_AGENT    = 'code_review'
    OPENCLAW_IDENTITY = '/var/lib/jenkins/.openclaw/identity.json'
    OPENCLAW_TIMEOUT  = '300'
  }
  steps {
    script {
      // Pass the Gerrit change URL directly
      def changeUrl = env.GERRIT_CHANGE_URL
      sh """
        python3 /path/to/openclaw.py \\
          --no-verify-ssl \\
          --quiet \\
          "\${changeUrl}" > review.md
      """
      // Optionally archive or post the report
      archiveArtifacts artifacts: 'review.md'
    }
  }
}
```

### Sending Gerrit Event Stream JSON via stdin

```bash
# Pipe a Gerrit event JSON directly
echo '{"type":"patchset-created","change":{"url":"https://gerrit.example.com/c/repo/+/42",...}}' \
  | python3 openclaw.py --stdin --agent code_review --no-verify-ssl
```

---

## Examples

```bash
# Using a Gerrit change URL
python3 openclaw.py --url 'wss://172.16.120.13?token=claw' \
  --agent code_review --identity ~/.openclaw/identity.json --no-verify-ssl \
  'https://gerrit.t2mobile.com/c/quicl/device/t2m/common/+/129701'

# Using a Gerrit change ID
python3 openclaw.py --url 'wss://172.16.120.13?token=claw' \
  --agent code_review --no-verify-ssl \
  'I803eaa5c943630355ae007c6f6cc888253250faa'

# Pipe a raw Gerrit event from stdin (e.g. from stream-events)
ssh gerrit gerrit stream-events | while read line; do
  echo "$line" | python3 openclaw.py --stdin --agent code_review --no-verify-ssl --quiet
done

# Suppress streaming output (only print final response)
python3 openclaw.py --quiet --agent code_review --no-verify-ssl \
  'https://gerrit.example.com/c/repo/+/99'
```

---

## Output

The script streams the agent's response to stdout as it arrives. When the agent finishes, the full Markdown report has been printed. Exit code is `0` on success, non-zero on error.

---

## Files

| File | Description |
|---|---|
| `openclaw.py` | Main Python WebSocket client |
| `requirements.txt` | Python package dependencies |
| `README.md` | This file |
