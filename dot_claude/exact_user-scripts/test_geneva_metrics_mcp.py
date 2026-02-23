# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp"]
# ///
"""Smoke test for geneva-metrics-mcp.csx MCP server using the official MCP Python client."""

import asyncio
import os
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    script_path = r"C:\Users\jubayard\.claude\user-scripts\geneva-metrics-mcp.csx"
    server_params = StdioServerParameters(
        command="dotnet",
        args=["script", script_path],
        # Pass full OS environment; the mcp default strips almost everything,
        # which breaks dotnet-script (needs USERPROFILE, DOTNET_ROOT, etc.)
        env=dict(os.environ),
    )

    print("Connecting to geneva-metrics-mcp.csx (may take a while for NuGet restore)...")
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            print(f"  Connected!\n")

            # ── 1. List tools ──────────────────────────────────────────
            print("1. Listing tools...")
            response = await session.list_tools()
            tool_names = sorted(t.name for t in response.tools)
            print(f"   Found {len(response.tools)} tools: {tool_names}")

            expected = sorted([
                "execute_kqlm",
                "get_namespaces",
                "get_metric_names",
                "get_dimension_names",
                "get_dimension_values",
                "get_preaggregates",
                "get_timeseries",
            ])
            assert tool_names == expected, f"Tool mismatch!\n  Expected: {expected}\n  Got:      {tool_names}"
            print("   [PASS] All expected tools present\n")

            # ── 2. Call get_namespaces (expect auth error, not crash) ──
            print("2. Calling get_namespaces (expecting graceful auth error)...")
            result = await session.call_tool("get_namespaces", {
                "monitoringAccount": "TestAccount",
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            # Should return an error string (auth failure), not throw
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            # ── 3. Call execute_kqlm (expect auth error, not crash) ────
            print("3. Calling execute_kqlm (expecting graceful auth error)...")
            result = await session.call_tool("execute_kqlm", {
                "monitoringAccount": "TestAccount",
                "metricNamespace": "TestNamespace",
                "query": 'metric("TestMetric").samplingTypes("Sum")',
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            # ── 4. Call get_dimension_names (expect auth error) ────────
            print("4. Calling get_dimension_names (expecting graceful auth error)...")
            result = await session.call_tool("get_dimension_names", {
                "monitoringAccount": "TestAccount",
                "metricNamespace": "TestNamespace",
                "metricName": "TestMetric",
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            # ── 5. Call get_dimension_values ───────────────────────────
            print("5. Calling get_dimension_values (expecting graceful auth error)...")
            result = await session.call_tool("get_dimension_values", {
                "monitoringAccount": "TestAccount",
                "metricNamespace": "TestNamespace",
                "metricName": "TestMetric",
                "dimensionName": "Datacenter",
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            # ── 6. Call get_preaggregates ──────────────────────────────
            print("6. Calling get_preaggregates (expecting graceful auth error)...")
            result = await session.call_tool("get_preaggregates", {
                "monitoringAccount": "TestAccount",
                "metricNamespace": "TestNamespace",
                "metricName": "TestMetric",
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            # ── 7. Call get_timeseries ─────────────────────────────────
            print("7. Calling get_timeseries (expecting graceful auth error)...")
            result = await session.call_tool("get_timeseries", {
                "monitoringAccount": "TestAccount",
                "metricNamespace": "TestNamespace",
                "metricName": "TestMetric",
                "samplingTypes": "Sum,Count",
                "dimensionFiltersJson": '[{"name":"Datacenter","values":["EastUS"]}]',
                "top": 5,
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            # ── 8. Call get_metric_names ───────────────────────────────
            print("8. Calling get_metric_names (expecting graceful auth error)...")
            result = await session.call_tool("get_metric_names", {
                "monitoringAccount": "TestAccount",
                "metricNamespace": "TestNamespace",
            })
            text = result.content[0].text
            print(f"   Response: {text[:200]}")
            assert isinstance(text, str) and len(text) > 0, "Expected non-empty text response"
            print("   [PASS] Tool executed and returned text\n")

            print("=== All 8 tests passed! ===")


if __name__ == "__main__":
    asyncio.run(main())
