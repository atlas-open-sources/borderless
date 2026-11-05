status: green — local budget adapter tested; Meta-side cap does not exist

# Validation, October 28, 2026

- 11 unit tests passed, including concurrent reservations against one database, exact exhaustion, restart persistence, missing storage, exclusive initialization, settlement, overrun halt, invalid input/usage, timeout holds and refusal before inference when insufficient budget remains.
- Python compilation passed. ResourceWarning checks passed after explicitly closing SQLite connections.
- `.env` and `.budget/ledger.sqlite3` are Git-ignored. Ledger and key file have owner-only permissions.
- Two synthetic live requests exercised the saved key through the protected adapter. The first hit its deliberately small 64-output-token limit during reasoning and returned incomplete; reported usage was still charged. The second, with a 512-token allowance, completed with text output.
- Total locally accounted live cost: $0.00190525. Remaining cumulative allowance: $19.99809475. No pending reservations, no halted flag. These are usage-based local calculations, not a billing-dashboard reconciliation.
- No audio, private conversation, deployment, glasses integration or account-wide spend enforcement was tested. Raw keys and provider response content were not retained in this report.

Implementation and use: [BUDGET.md](BUDGET.md).
