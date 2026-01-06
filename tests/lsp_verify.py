#!/usr/bin/env python3
import subprocess
import json
import sys
import time

# CONFIG
LSP_BINARY = "./zig-out/bin/janus-lsp"

def rpc_encode(method, params=None, msg_id=None):
    payload = {
        "jsonrpc": "2.0",
        "method": method
    }
    if params:
        payload["params"] = params
    if msg_id is not None:
        payload["id"] = msg_id
    
    body = json.dumps(payload)
    return f"Content-Length: {len(body)}\r\n\r\n{body}"

def run_test():
    print(f"⚡ Spawning {LSP_BINARY}...")
    proc = subprocess.Popen(
        [LSP_BINARY],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,  # Merge stderr into stdout for tracer visibility
        text=True,
        bufsize=0
    )

    # 1. HANDSHAKE (Initialize)
    print(">> Sending initialize...")
    init_msg = rpc_encode("initialize", {
        "processId": 1234,
        "rootUri": "file:///tmp/janus-test",
        "capabilities": {}
    }, msg_id=1)
    proc.stdin.write(init_msg)
    proc.stdin.flush()

    print("<< Waiting for handshake...")
    time.sleep(0.5)
    
    # 2. INITIALIZED notification
    print(">> Sending initialized notification...")
    initialized_msg = rpc_encode("initialized", {})
    proc.stdin.write(initialized_msg)
    proc.stdin.flush()

    # 3. OPEN DOCUMENT (Valid Code)
    print(">> Sending textDocument/didOpen (Valid)...")
    open_msg = rpc_encode("textDocument/didOpen", {
        "textDocument": {
            "uri": "file:///tmp/test.jan",
            "languageId": "janus",
            "version": 1,
            "text": "func main() do\n    println(\"Hello\")\nend"
        }
    })
    proc.stdin.write(open_msg)
    proc.stdin.flush()
    time.sleep(0.2)

    # 4. CHANGE DOCUMENT (Break it - Remove 'end')
    print(">> Sending textDocument/didChange (Broken - No 'end')...")
    change_msg = rpc_encode("textDocument/didChange", {
        "textDocument": {
            "uri": "file:///tmp/test.jan",
            "version": 2
        },
        "contentChanges": [{
            "text": "func main() do\n    println(\"Hello\")\n"
        }]
    })
    proc.stdin.write(change_msg)
    proc.stdin.flush()

    # 5. LISTEN FOR THE SCREAM
    print("<< Listening for publishDiagnostics...")
    
    start_time = time.time()
    buffer = ""
    diagnostics_found = False
    
    while time.time() - start_time < 3.0:
        # Read available data without blocking
        import select
        ready = select.select([proc.stdout], [], [], 0.1)
        if ready[0]:
            chunk = proc.stdout.read(1024)
            if not chunk:
                break
            buffer += chunk
            
            if "publishDiagnostics" in buffer:
                diagnostics_found = True
                break

    if diagnostics_found:
        print("\\n🚨 VICTORY: Received publishDiagnostics!")
        print("Buffer tail:")
        print(buffer[-500:])
        proc.terminate()
        proc.wait(timeout=2)
        return True
    else:
        print("\\n❌ FAILURE: Timed out waiting for diagnostics.")
        print("Buffer content:", buffer[:1000])
        
        # Check stderr for errors
        proc.terminate()
        proc.wait(timeout=2)
        stderr_output = proc.stderr.read()
        if stderr_output:
            print("\\nStderr:", stderr_output)
        return False

if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
