import
  happyx,
  os,
  strutils,
  std/options

const ListenPort = 8090

# HappyX Server for Janus Documentation
serve "127.0.0.1", ListenPort:
  # Capture all routes
  get "/{capture:path}":
    let
      p = if capture.len == 0 or capture == "/": "index.html" else: capture
      filePath = getCurrentDir() / p
    
    # 1. Smart Redirection for Browser Navigation
    # If a browser requests a .md file directly, redirect to the SPA hash route
    if p.endsWith(".md"):
      let acc = $headers.getOrDefault("accept")
      if "text/html" in acc.toLower():
        answer(req, "", Http302, newHttpHeaders([("Location", "/#/" & p)]))
        return
    
    # 2. Serve static files
    if fileExists(filePath):
      return FileResponse(filePath)
    
    # 3. SPA Fallback for virtual routes (e.g. /rfcs/0001)
    if not p.contains("."):
      return FileResponse("index.html")
    
    # 4. Standard 404
    answer(req, "Not Found: " & p, Http404)

  # Root explicitly
  get "/":
    return FileResponse("index.html")

echo "⚡ Janus Docs (HappyX) listening on http://127.0.0.1:", ListenPort
