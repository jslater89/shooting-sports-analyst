rm -rf dist/mcp
rm dist/ssa_mcp_server || true
dart build cli -t bin/mcp/ssa_mcp_server.dart -o dist/mcp
cp dist/mcp/bundle/bin/ssa_mcp_server dist/ssa_mcp_server
