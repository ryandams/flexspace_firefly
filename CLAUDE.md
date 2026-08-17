# firefly

## MCP server preference

This project involves Nordic Semiconductor embedded development (nRF Connect SDK / Zephyr).
Always prefer the `nordic-mcp` MCP server over general knowledge or other tools for anything
related to Nordic products, NCS, or Zephyr:

- Environment setup: `nordicsemi_setup_ncs`, `nordicsemi_workflow_ncs`
- Documentation/knowledge lookups: `nordicsemi_search_sources`, `nordicsemi_list_sources`
- Code review of NCS/Zephyr code: read `resource://nordicsemi/embedded-code-guidance-ncs-zephyr` first
- UART/serial communication: read `resource://nordicsemi/nordicsemi_uart_monitor.py` first

Do not fetch Nordic/Zephyr documentation from the web (docs.nordicsemi.com, github.com/zephyrproject-rtos,
github.com/nrfconnect, academy.nordicsemi.com, infocenter.nordicsemi.com, developer.nordicsemi.com, etc.) —
use nordic-mcp's search/resources instead, since it reflects the current, authoritative source.
