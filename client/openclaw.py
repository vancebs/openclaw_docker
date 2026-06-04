#!/usr/bin/env python3
"""
openclaw.py - OpenClaw WebSocket client for Jenkins CI integration.

Connects to an OpenClaw gateway, sends a message to a specified agent,
and prints the streaming response.

Usage:
    python3 openclaw.py [OPTIONS] <message>

Example:
    python3 openclaw.py --agent code-review "https://gerrit.example.com/c/my-repo/+/12345"
    echo '{"type":"patchset-created",...}' | python3 openclaw.py --agent code-review --stdin
"""

import argparse
import asyncio
import base64
import hashlib
import json
import os
import ssl
import sys
import uuid
from pathlib import Path

import websockets

# ── Ed25519 device identity ───────────────────────────────────────────────────

def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def _b64url_decode(s: str) -> bytes:
    padding = "=" * ((4 - len(s) % 4) % 4)
    return base64.urlsafe_b64decode(s + padding)

def _ed25519_spki_prefix() -> bytes:
    return bytes.fromhex("302a300506032b6570032100")

def _ed25519_pkcs8_prefix() -> bytes:
    return bytes.fromhex("302e020100300506032b657004220420")

def _public_key_raw(public_key_pem: str) -> bytes:
    """Extract 32-byte raw Ed25519 public key from PEM."""
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.hazmat.primitives.serialization import load_pem_public_key
    key = load_pem_public_key(public_key_pem.encode())
    raw_spki = key.public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
    prefix = _ed25519_spki_prefix()
    if raw_spki[:len(prefix)] == prefix:
        return raw_spki[len(prefix):]
    return raw_spki

def _fingerprint(public_key_pem: str) -> str:
    """SHA-256 hex fingerprint of the raw public key bytes (= device ID)."""
    return hashlib.sha256(_public_key_raw(public_key_pem)).hexdigest()

def _public_key_raw_b64url(public_key_pem: str) -> str:
    return _b64url_encode(_public_key_raw(public_key_pem))

def _sign(private_key_pem: str, payload: str) -> str:
    """Sign a UTF-8 string with Ed25519 and return base64url-encoded signature."""
    from cryptography.hazmat.primitives.serialization import load_pem_private_key
    key = load_pem_private_key(private_key_pem.encode(), password=None)
    sig = key.sign(payload.encode("utf-8"))
    return _b64url_encode(sig)

def generate_identity() -> dict:
    """Generate a new Ed25519 device identity (transient, not persisted)."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import (
        Encoding, PrivateFormat, PublicFormat, NoEncryption
    )
    priv = Ed25519PrivateKey.generate()
    pub = priv.public_key()
    pub_pem = pub.public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()
    priv_pem = priv.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()).decode()
    device_id = _fingerprint(pub_pem)
    return {"deviceId": device_id, "publicKeyPem": pub_pem, "privateKeyPem": priv_pem}

def load_or_create_identity(identity_file: str | None) -> dict:
    """Load identity from file, or generate a new one (optionally persist it)."""
    if identity_file:
        p = Path(identity_file)
        if p.exists():
            try:
                data = json.loads(p.read_text())
            except (json.JSONDecodeError, ValueError) as e:
                raise RuntimeError(
                    f"Identity file '{identity_file}' is not valid JSON: {e}"
                ) from e
            return data
        identity = generate_identity()
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(identity, indent=2))
        except OSError as e:
            raise RuntimeError(
                f"Cannot write identity file '{identity_file}': {e}"
            ) from e
        return identity
    return generate_identity()

def build_device_auth_payload_v3(
    device_id: str, client_id: str, client_mode: str, role: str,
    scopes: list[str], signed_at_ms: int, token: str, nonce: str,
    platform: str, device_family: str = ""
) -> str:
    """Build the v3 auth payload string to be signed."""
    def _norm(s: str) -> str:
        # Mirror normalizeDeviceMetadataForAuth: trim + lowercase, empty → ""
        return (s or "").strip().lower()
    return "|".join([
        "v3",
        device_id, client_id, client_mode, role,
        ",".join(scopes),
        str(signed_at_ms),
        token or "",
        nonce,
        _norm(platform),
        _norm(device_family),
    ])

# ── Gateway client ────────────────────────────────────────────────────────────

class OpenClawClient:
    """
    Minimal async OpenClaw gateway client.

    Authenticates with Ed25519 device identity, creates a session with the
    specified agent, sends a message, and streams the response back.
    """

    def __init__(
        self,
        url: str,
        token: str,
        agent: str,
        timeout: float = 300.0,
        identity_file: str | None = None,
        verify_ssl: bool = True,
    ):
        self.url = url
        self.token = token
        self.agent = agent
        self.timeout = timeout
        self.identity_file = identity_file
        self.verify_ssl = verify_ssl
        self._pending: dict[str, asyncio.Future] = {}
        self._ws = None
        self._loop = None

    # ── Low-level message handling ────────────────────────────────────────────

    async def _send(self, obj: dict):
        await self._ws.send(json.dumps(obj))

    async def _request(self, method: str, params: dict | None = None) -> dict:
        req_id = str(uuid.uuid4())
        future = self._loop.create_future()
        self._pending[req_id] = future
        msg = {"type": "req", "id": req_id, "method": method}
        if params is not None:
            msg["params"] = params
        await self._send(msg)
        try:
            return await asyncio.wait_for(future, timeout=self.timeout)
        except TimeoutError:
            self._pending.pop(req_id, None)
            raise TimeoutError(
                f"Gateway did not respond to '{method}' within {self.timeout:.0f}s"
            )
        except asyncio.CancelledError:
            self._pending.pop(req_id, None)
            raise RuntimeError(
                f"Request '{method}' was cancelled (connection lost)"
            ) from None

    async def _dispatch(self, on_event):
        """Dispatch incoming messages – runs until the connection closes."""
        try:
            async for raw in self._ws:
                msg = json.loads(raw)
                mtype = msg.get("type")
                if mtype == "res":
                    fut = self._pending.pop(msg["id"], None)
                    if fut and not fut.done():
                        if msg.get("ok"):
                            fut.set_result(msg.get("payload") or {})
                        else:
                            err = msg.get("error", {})
                            fut.set_exception(
                                RuntimeError(err.get("message", "gateway error"))
                            )
                elif mtype == "event":
                    await on_event(msg)
        except Exception:
            # Cancel all pending requests, then re-raise so the caller knows
            # the connection is gone (do NOT swallow the exception here).
            for fut in self._pending.values():
                if not fut.done():
                    fut.cancel()
            raise

    # ── Connection & authentication ───────────────────────────────────────────

    async def _connect(self, ws) -> None:
        """Perform the OpenClaw gateway handshake (challenge → connect)."""
        # 1. Receive connect.challenge
        raw = await asyncio.wait_for(ws.recv(), timeout=10)
        challenge = json.loads(raw)
        if challenge.get("event") != "connect.challenge":
            raise RuntimeError(
                f"Unexpected first message from gateway: {challenge}"
            )
        nonce = challenge["payload"]["nonce"]

        # 2. Build Ed25519 device identity and sign the connect payload
        identity = load_or_create_identity(self.identity_file)
        device_id = identity["deviceId"]
        pub_b64 = _public_key_raw_b64url(identity["publicKeyPem"])
        role = "operator"
        scopes = [
            "operator.admin",
            "operator.read",
            "operator.write",
            "operator.approvals",
            "operator.pairing",
        ]
        signed_at_ms = int(__import__("time").time() * 1000)
        payload_str = build_device_auth_payload_v3(
            device_id=device_id,
            client_id="cli",
            client_mode="backend",
            role=role,
            scopes=scopes,
            signed_at_ms=signed_at_ms,
            token=self.token,
            nonce=nonce,
            platform=sys.platform,
        )
        signature = _sign(identity["privateKeyPem"], payload_str)

        # 3. Send connect request
        req_id = str(uuid.uuid4())
        future = self._loop.create_future()
        self._pending[req_id] = future
        await ws.send(json.dumps({
            "type": "req",
            "id": req_id,
            "method": "connect",
            "params": {
                "minProtocol": 4,
                "maxProtocol": 4,
                "client": {
                    "id": "cli",
                    "displayName": "openclaw-python-client",
                    "version": "1.0.0",
                    "platform": sys.platform,
                    "mode": "backend",
                },
                "auth": {"token": self.token},
                "role": role,
                "scopes": scopes,
                "device": {
                    "id": device_id,
                    "publicKey": pub_b64,
                    "signature": signature,
                    "signedAt": signed_at_ms,
                    "nonce": nonce,
                },
            },
        }))

        # Read messages directly until we get the connect response.
        # (_dispatch hasn't started yet, so we can't use the future.)
        deadline = __import__("time").monotonic() + 10
        while True:
            remaining = deadline - __import__("time").monotonic()
            if remaining <= 0:
                raise TimeoutError("Timed out waiting for connect response")
            raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
            msg = json.loads(raw)
            if msg.get("type") == "res" and msg.get("id") == req_id:
                self._pending.pop(req_id, None)
                if msg.get("ok"):
                    return msg.get("payload") or {}
                err = msg.get("error") or {}
                raise RuntimeError(err.get("message", "connect failed"))
            # Buffer other messages (e.g. health events) for dispatch
            # by putting them back via a queue would be complex;
            # in practice the connect response arrives almost immediately.

    # ── High-level: send a message and stream the response ───────────────────

    async def run(self, message: str, on_chunk=None, on_done=None) -> str:
        """
        Connect to the gateway, send *message* to the configured agent,
        collect all text chunks and return the full response string.

        Args:
            message:  The text to send to the agent.
            on_chunk: Optional callback(str) called for each streamed chunk.
            on_done:  Optional callback(str) called once with the full response.

        Returns:
            The complete agent response as a string.
        """
        ssl_ctx = ssl.create_default_context()
        if not self.verify_ssl:
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE

        self._loop = asyncio.get_event_loop()
        full_response: list[str] = []
        session_key: str | None = None
        done_event = asyncio.Event()
        run_id: str | None = None
        run_status: list[str | None] = [None]        # set by sessions.changed
        conn_error: list[BaseException | None] = [None]  # set if dispatch loop dies

        async def on_event(msg: dict):
            nonlocal run_id
            event = msg.get("event", "")
            payload = msg.get("payload") or {}

            if event == "agent":
                # Filter strictly: only process events for our session and run.
                # The gateway provides both sessionKey and runId on every agent event.
                if payload.get("sessionKey") != session_key:
                    return
                if run_id is not None and payload.get("runId") != run_id:
                    return

                stream = payload.get("stream")
                data = payload.get("data") or {}

                if stream == "assistant":
                    # Use the gateway-provided `delta` field (incremental text).
                    # Falling back to `text` (full snapshot) only if `delta` is absent
                    # (for forward-compatibility with older gateway versions).
                    delta = data.get("delta") or data.get("text") or ""
                    if delta:
                        full_response.append(delta)
                        if on_chunk:
                            on_chunk(delta)

                elif stream == "lifecycle":
                    if data.get("phase") == "end":
                        done_event.set()

            elif event == "sessions.changed":
                if payload.get("sessionKey") == session_key:
                    run = payload.get("run") or {}
                    status = run.get("status")
                    if status in ("done", "error", "cancelled", "timeout"):
                        run_status[0] = status
                        done_event.set()

        async def _dispatch_guarded():
            """Run _dispatch and capture any exception; always unblock done_event."""
            try:
                await self._dispatch(on_event)
            except Exception as e:
                conn_error[0] = e
            finally:
                # Unblock done_event.wait() so run() doesn't hang if the
                # connection drops before the agent run completes.
                done_event.set()

        async with websockets.connect(
            self.url,
            ssl=ssl_ctx,
            open_timeout=30,
            additional_headers={"User-Agent": "openclaw-python-client/1.0"},
        ) as ws:
            self._ws = ws

            # Authenticate
            await self._connect(ws)

            # Start background dispatcher
            dispatch_task = asyncio.create_task(_dispatch_guarded())

            try:
                # Subscribe to session events (required to receive sessions.changed)
                await self._request("sessions.subscribe", {})

                # Create session for the target agent
                create_resp = await self._request("sessions.create", {
                    "agentId": self.agent,
                })
                session_key = create_resp.get("key")
                if not session_key:
                    raise RuntimeError(
                        f"sessions.create did not return a key: {create_resp}"
                    )

                # Subscribe to streaming message chunks for this session
                await self._request("sessions.messages.subscribe", {"key": session_key})

                # Send the user message
                send_resp = await self._request("sessions.send", {
                    "key": session_key,
                    "message": message,
                })
                run_id = send_resp.get("runId")

                # Wait for the run to complete
                try:
                    await asyncio.wait_for(done_event.wait(), timeout=self.timeout)
                except TimeoutError:
                    raise TimeoutError(
                        f"Agent '{self.agent}' did not complete within "
                        f"{self.timeout:.0f}s "
                        f"(session: {session_key}, runId: {run_id})"
                    )

                # Check if the dispatch loop died (e.g. connection dropped mid-run)
                if conn_error[0] is not None:
                    raise RuntimeError(
                        f"WebSocket connection lost during agent run: {conn_error[0]}"
                    ) from conn_error[0]

                # Check if the agent run ended in a non-success state
                status = run_status[0]
                if status is not None and status != "done":
                    raise RuntimeError(
                        f"Agent run ended with status '{status}' "
                        f"(session: {session_key}, runId: {run_id})"
                    )

            finally:
                dispatch_task.cancel()
                try:
                    await dispatch_task
                except (asyncio.CancelledError, Exception):
                    pass

        result = "".join(full_response)
        if on_done:
            on_done(result)
        return result


# ── CLI entrypoint ────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="openclaw.py",
        description=(
            "Send a message to an OpenClaw agent and print the response.\n\n"
            "Typical Jenkins usage:\n"
            "  python3 openclaw.py --agent code-review \\\n"
            "      --url 'wss://openclaw-host?token=YOUR_TOKEN' \\\n"
            "      'https://gerrit.example.com/c/repo/+/12345'"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "message",
        nargs="?",
        default=None,
        help="Message to send to the agent (use --stdin to read from stdin)",
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("OPENCLAW_URL", ""),
        help=(
            "WebSocket URL of the OpenClaw gateway, e.g. "
            "wss://host?token=TOKEN  (env: OPENCLAW_URL)"
        ),
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("OPENCLAW_TOKEN", ""),
        help="Gateway auth token (env: OPENCLAW_TOKEN). "
             "Ignored if token is already embedded in --url.",
    )
    parser.add_argument(
        "--agent",
        default=os.environ.get("OPENCLAW_AGENT", "main"),
        help="Agent ID to chat with (env: OPENCLAW_AGENT, default: main)",
    )
    parser.add_argument(
        "--stdin",
        action="store_true",
        help="Read message from stdin instead of positional argument",
    )
    parser.add_argument(
        "--identity",
        default=os.environ.get("OPENCLAW_IDENTITY", ""),
        metavar="FILE",
        help=(
            "Path to a JSON file for persisting the Ed25519 device identity. "
            "If omitted a temporary identity is generated per invocation. "
            "(env: OPENCLAW_IDENTITY)"
        ),
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.environ.get("OPENCLAW_TIMEOUT", "300")),
        help="Seconds to wait for the agent response (default: 300)",
    )
    parser.add_argument(
        "--no-verify-ssl",
        action="store_true",
        help="Disable SSL certificate verification (useful for self-signed certs)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress streaming output; only print the final response",
    )
    return parser


def resolve_url_and_token(args) -> tuple[str, str]:
    url = args.url.strip()
    token = args.token.strip()

    if not url:
        # Try to build from host + token
        host = os.environ.get("OPENCLAW_HOST", "").strip()
        if host:
            scheme = "wss" if not host.startswith("ws") else ""
            url = f"{scheme}{'://' if scheme else ''}{host}"
        else:
            print("ERROR: --url is required (or set OPENCLAW_URL)", file=sys.stderr)
            sys.exit(1)

    # If token is not in the URL but provided separately, append it
    if token and "token=" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}token={token}"

    # Extract token from URL if not provided separately
    if not token:
        import urllib.parse
        parsed = urllib.parse.urlparse(url)
        qs = urllib.parse.parse_qs(parsed.query)
        token = (qs.get("token") or [""])[0]

    return url, token


def main():
    parser = build_parser()
    args = parser.parse_args()

    # Resolve message
    if args.stdin:
        message = sys.stdin.read().strip()
    elif args.message:
        message = args.message.strip()
    else:
        parser.print_help()
        sys.exit(1)

    if not message:
        print("ERROR: Message is empty", file=sys.stderr)
        sys.exit(1)

    url, token = resolve_url_and_token(args)

    client = OpenClawClient(
        url=url,
        token=token,
        agent=args.agent,
        timeout=args.timeout,
        identity_file=args.identity or None,
        verify_ssl=not args.no_verify_ssl,
    )

    def on_chunk(chunk: str):
        if not args.quiet:
            print(chunk, end="", flush=True)

    async def run():
        result = await client.run(message, on_chunk=on_chunk)
        if args.quiet:
            print(result)
        elif not result.endswith("\n"):
            print()  # ensure final newline
        return result

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)
    except SystemExit:
        raise
    except Exception as e:
        # str(e) can be empty for some built-in exceptions (e.g. bare TimeoutError)
        msg = str(e) or type(e).__name__
        print(f"\nERROR: {msg}", file=sys.stderr)
        sys.exit(1)
    except BaseException as e:
        # Safety net for CancelledError and other BaseException subclasses
        # that are not caught by `except Exception` in Python 3.8+.
        print(f"\nERROR: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
