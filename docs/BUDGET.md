# $20 project budget

Implemented October 28, 2026. User authorized a cumulative $20 for this experiment. No monthly reset, automatic top-up or CLI override exists.

## Use

Run from this project folder:

```sh
python3 -m budget_relay status
printf '%s' 'Translate into Mandarin: Hello.' | python3 -m budget_relay generate --max-output-tokens 128
python3 -m unittest discover -s tests -v
```

Applications can use `Relay(Ledger(LEDGER), transport()).generate(text, max_output_tokens)` from `budget_relay.core` and `budget_relay.__main__`. This is a local CLI and in-process provider adapter, not a deployed HTTP server. No process stays running after a command exits.

## Enforcement

The fixed ledger is `.budget/ledger.sqlite3`, private and Git-ignored. Reservations and settlement use SQLite transactions, shared across concurrent processes. Missing/corrupt storage fails closed. Initialization is explicit and exclusive; normal commands never create/reset a ledger. Preserve this file across app restarts and deployments. Do not delete it to recover budget.

Only standard `muse-spark-1.3`, plain-text stateless non-streaming Responses calls are exposed. Tools, remote files, previous responses, background requests, other models, audio and arbitrary endpoints cannot be passed through this adapter. Output is capped at 2048 tokens and rendered input at 16384 tokens. No automatic retries.

Before inference, the adapter gets a rendered token count, then reserves twice the sum of full-price input cost and maximum output cost. The count is a context measurement rather than a billing quote; the text-only/no-tool restriction avoids tool-loop context growth. Successful reported usage settles at full uncached input and output rates. Missing usage, network ambiguity and process death retain the full reservation indefinitely. An observed charge exceeding its reservation halts further calls for review. No prompt, result or key is stored in the ledger.

Provider credentials are loaded directly from `.env`, never passed in command-line arguments or logged. Requests use a fixed HTTPS origin, reject redirects and have a 45-second timeout. `store=false` is requested; this does not claim organization-level zero data retention.

## Limits of the protection

This enforces a conservative local accounted budget, not a Meta-side billing cap. It covers only calls routed through this adapter and this ledger. Direct SDK/curl calls, Playground, other machines, deletion/editing of accounting files, price changes or provider accounting deviations are outside that guarantee. The ledger starts with this implementation; it does not import historical account charges. Credit claims do not replenish the $20 allowance.

Voice implementation is authorized. Bound session duration and transmitted audio, retain usage evidence, and keep total authorized spending within $20; the current text adapter does not meter voice. There is no claim that the planned glasses app is already integrated.

Review prices before adding models or changing the event scope. Rates verified October 28: Spark Standard input $1.25/M and output $4.25/M. The implementation deliberately ignores cache discounts. Sources: [pricing](https://dev.meta.ai/docs/pricing-rate-limits), [token count semantics](https://dev.meta.ai/docs/token-counting), [Responses](https://dev.meta.ai/docs/protocols/responses), [Meta alerts are not caps](https://dev.meta.ai/help/billing/spend-limit-alert).
