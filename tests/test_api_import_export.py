import os
import sys
import time
import shutil
import subprocess
import json
import urllib.request

ROOT_DIR = "/home/nc568/antigravity/hopeful-volta/fossil-nim"
BIN_FOSSIL = os.path.join(ROOT_DIR, "bin/fossil")
TEST_DIR = "/tmp/fossil-api-io-test"
REPO_PATH = os.path.join(TEST_DIR, "test.fossil")
CHECKOUT_DIR = os.path.join(TEST_DIR, "checkout")
PORT = 8093
BASE_URL = f"http://127.0.0.1:{PORT}"

if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)
os.makedirs(CHECKOUT_DIR, exist_ok=True)

try:
    # 1. Init & create files
    subprocess.run(f"{BIN_FOSSIL} init {REPO_PATH}", shell=True, check=True)
    subprocess.run(f"{BIN_FOSSIL} open {REPO_PATH}", shell=True, cwd=CHECKOUT_DIR, check=True)
    with open(os.path.join(CHECKOUT_DIR, "test.txt"), "w") as f:
        f.write("Hello Fossil API")
    subprocess.run(f"{BIN_FOSSIL} add test.txt", shell=True, cwd=CHECKOUT_DIR, check=True)
    subprocess.run(f'{BIN_FOSSIL} commit -m "Initial commit via API test"', shell=True, cwd=CHECKOUT_DIR, check=True)
    subprocess.run(f'{BIN_FOSSIL} wiki create Home "Welcome to API Test Repo"', shell=True, cwd=CHECKOUT_DIR, check=True)
    subprocess.run(f'{BIN_FOSSIL} ticket create "Test Issue 1" "Description for issue 1"', shell=True, cwd=CHECKOUT_DIR, check=True)

    # 2. Start server
    proc = subprocess.Popen([BIN_FOSSIL, "server", "--port", str(PORT), "--bind", "127.0.0.1"], cwd=CHECKOUT_DIR)
    time.sleep(1.5)

    # 3. Test Export
    req = urllib.request.Request(f"{BASE_URL}/api/v1/repo/export")
    with urllib.request.urlopen(req, timeout=5) as resp:
        export_data = json.loads(resp.read().decode())
    print("Export Response:", json.dumps(export_data, indent=2)[:300], "...")
    assert export_data.get("ok") is True
    bundle = export_data["data"]
    assert bundle["format"] == "fossil-nim-bundle"
    ev_count = len(bundle["events"])
    wiki_count = len(bundle["wiki"])
    ticket_count = len(bundle["tickets"])
    print(f"Export OK! Events: {ev_count}, Files: {len(bundle['files'])}, Wiki: {wiki_count}, Tickets: {ticket_count}")
    assert ev_count >= 1
    assert wiki_count >= 1
    assert ticket_count >= 1

    # 4. Test Import (Merge Mode)
    import_payload = {
        "mode": "merge",
        "events": [
            {
                "type": "ci",
                "mtime": time.time(),
                "user": "merger",
                "comment": "Imported continuation commit",
                "branch": "trunk"
            }
        ],
        "files": [{"path": "imported_new.txt"}],
        "wiki": [{"name": "ImportedWiki", "text": "This wiki was imported", "author": "tester"}],
        "tickets": [{"id": "tkt-imported-999", "title": "Imported Ticket", "desc": "Imported via merge", "status": "Open", "priority": "High"}]
    }
    req = urllib.request.Request(
        f"{BASE_URL}/api/v1/repo/import",
        data=json.dumps(import_payload).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        import_res = json.loads(resp.read().decode())
    print("Import Merge Response:", import_res)
    assert import_res.get("ok") is True
    assert import_res["data"]["importedEvents"] == 1
    assert import_res["data"]["importedWiki"] == 1
    assert import_res["data"]["importedTickets"] == 1

    # Verify Export after merge contains both original and merged
    req = urllib.request.Request(f"{BASE_URL}/api/v1/repo/export")
    with urllib.request.urlopen(req, timeout=5) as resp:
        post_merge = json.loads(resp.read().decode())["data"]
    wiki_names = [w["name"] for w in post_merge["wiki"]]
    print("Wiki pages after merge:", wiki_names)
    assert "Home" in wiki_names
    assert "ImportedWiki" in wiki_names

    # 5. Test Import (Replace Mode)
    replace_payload = {
        "mode": "replace",
        "events": [
            {
                "type": "ci",
                "mtime": time.time(),
                "user": "clean_slate",
                "comment": "Clean slate commit only",
                "branch": "trunk"
            }
        ],
        "files": [{"path": "only_file.txt"}],
        "wiki": [{"name": "OnlyWiki", "text": "Only this wiki exists", "author": "tester"}],
        "tickets": [{"id": "tkt-only-1", "title": "Only Ticket", "desc": "Clean slate ticket", "status": "Closed", "priority": "Low"}]
    }
    req = urllib.request.Request(
        f"{BASE_URL}/api/v1/repo/import",
        data=json.dumps(replace_payload).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        replace_res = json.loads(resp.read().decode())
    print("Import Replace Response:", replace_res)
    assert replace_res.get("ok") is True
    assert replace_res["data"]["mode"] == "replace"

    # Verify Export after replace contains ONLY new data
    req = urllib.request.Request(f"{BASE_URL}/api/v1/repo/export")
    with urllib.request.urlopen(req, timeout=5) as resp:
        post_replace = json.loads(resp.read().decode())["data"]
    wiki_names_rep = [w["name"] for w in post_replace["wiki"]]
    print("Wiki pages after replace:", wiki_names_rep)
    assert "Home" not in wiki_names_rep
    assert "OnlyWiki" in wiki_names_rep
    assert len(post_replace["events"]) == 1

    print("\n>>> ALL REST API EXPORT/IMPORT TESTS PASSED SUCCESSFULLY! <<<")

finally:
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except:
        pass
    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
