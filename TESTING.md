# Testing

GAL-Sync has three kinds of tests. Only the first runs in CI.

| Kind                                    | Needs                            | Runs in CI | Checks                                     |
| --------------------------------------- | -------------------------------- | ---------- | ------------------------------------------ |
| [Unit tests](#unit-tests)               | PowerShell 7.6                   | yes        | the sync logic, against a fake Graph       |
| [Integration tests](#integration-tests) | a test tenant                    | on request | the real Microsoft Graph and Exchange      |
| [Dev Proxy check](#dev-proxy-check)     | Dev Proxy, a trusted certificate | no         | real HTTP transport, throttling and errors |

## Unit tests

```powershell
./scripts/build.ps1                  # analyze, test and package, like CI
./scripts/build.ps1 -Task Test       # tests only
./scripts/build.ps1 -Task Analyze    # formatting and PSScriptAnalyzer
./scripts/build.ps1 -Task Format     # fix formatting
```

`just` has the same recipes (`just test`, `just lint`, `just fmt`). Run `just setup` once to install Pester and PSScriptAnalyzer.

The tests run against `Tests/FakeGraph.ps1`, a stateful fake Microsoft Graph. It copies the module to a temp folder and replaces only the lowest layer, `Invoke-HttpRequest`. Everything above it is the real code, including auth, paging, `$batch`, retries and the plan that decides what to create, update and remove. It keeps users, groups, mailboxes, contact folders and contacts in memory, so a test can run a sync twice and look at the result.

Test helpers: `Add-FakeUser`, `Add-FakeGroup`, `Add-FakeOrgContact`, `Add-FakeFolder`, `Get-FakeContact`, and `Add-FakeFault` to make a request answer with a status such as 429 or 503 (optionally with `-RetryAfter`). `$Graph.Unlicensed` and `$Graph.AccessDenied` list mailboxes that answer with Exchange errors.

| File                    | Covers                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------- |
| `Connection.tests.ps1`  | sign-in methods, certificates, token lifetime and renewal                                         |
| `Directory.tests.ps1`   | who becomes a contact (filters, groups, mail contacts, hidden users) and Graph paging and retries |
| `MailboxSync.tests.ps1` | one mailbox: create, update, remove, results, retries                                             |
| `Run.tests.ps1`         | `Invoke-GALSync`, `Start-GALSync`, the runbook, `Sync-Contacts.ps1`                               |
| `Deployment.tests.ps1`  | `deploy/main.bicep` matches the module's settings and roles                                       |
| `Module.tests.ps1`      | the manifest and exported functions                                                               |

Limits: the fake is written by us, so it only knows what we know about Graph. It says nothing about real HTTP, TLS or what Exchange accepts.

## Integration tests

They run against a real test tenant and are skipped by default. Set `GALSYNC_TENANT_ID`, `GALSYNC_CLIENT_ID`, `GALSYNC_CLIENT_SECRET` and `GALSYNC_TEST_MAILBOX`, then:

```powershell
./scripts/build.ps1 -Task Test -Integration     # or: just test-integration
```

The `Integration` workflow (`.github/workflows/integration.yml`) runs the same on demand with those values as repository secrets. The app needs a user read permission (`User.Read.All`) and `Contacts.ReadWrite` for the test mailbox. The tests create a contact folder with a unique name in that mailbox and remove it again afterwards, so use a test mailbox.

No Graph or Exchange emulator was found (one search). A real tenant is the only way to check what Exchange does. A Microsoft 365 Developer Program sandbox is a free E5 tenant, but only some people qualify for one.

## Dev Proxy check

A manual check, not part of the build or CI. Files are in `Tests/DevProxy/`.

[Dev Proxy](https://devproxy.net) answers real HTTPS requests in place of Microsoft Graph. It covers what the in-process fake cannot: the real `Invoke-RestMethod` path, TLS, the `HTTPS_PROXY` handling, real `Retry-After` headers and the real waiting time. The retry logic itself is already unit tested, so this is a transport-level check.

It is **not** a Graph emulator. Mocks are stateless and written by hand, so it says nothing about whether the sync logic is right. Add logic checks to the unit tests.

### Run it

Needs [Dev Proxy](https://aka.ms/devproxy) (tested with 4.0.0).

```powershell
devproxy cert ensure     # once: trust the Dev Proxy root certificate (asks for your password)
just devproxy            # or: ./Tests/DevProxy/Invoke-DevProxyScenario.ps1
```

The script starts Dev Proxy, runs `Invoke-GALSync` through it, checks the results and stops it again. It takes about 10 seconds and exits with 1 when a check fails.

| Mailbox | What Dev Proxy answers                                                                  | Expected                                                      |
| ------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| ann     | 503 on the first users request, 429 once on the folder listing and on one `$batch` item | `Succeeded`, 2 created, only the throttled batch item retried |
| bob     | 429 with `Retry-After: 1` every time                                                    | `Failed` (`TooManyRequests`) after 5 retries                  |
| carl    | 403 `ErrorAccessDenied`                                                                 | `Failed`, with the `Contacts.ReadWrite` / Exchange RBAC hint  |

### How it works

- `devproxyrc.json` uses only `MockResponsePlugin` and watches `graph.microsoft.com` and `login.microsoftonline.com`. `blockUnmockedRequests` is on, so a request without a mock fails with 502 instead of reaching the real Graph.
- `mocks.json` holds the answers. `nth` picks the first or second request that matches a mock, which is how a throttled request succeeds on the retry. The token mock is an unsigned JWT that expires in 2100 and carries `User.Read.All` and `Contacts.ReadWrite`. The module only reads its claims.
- The module hardcodes both hostnames, so intercepting them is the only way in. Only the script's own process uses the proxy (`HTTPS_PROXY`).

### Things to know

- Dev Proxy turns itself on as the **system proxy** by default. The script passes `--as-system-proxy false`. If you start it by hand, pass it too, or run `devproxy stop`, otherwise your whole machine keeps using the proxy.
- When the module sends a new request, add a mock for it, or the check fails with a 502. Mocks must match the URLs the module sends (`%40` in mailbox names, the `?` query).
- Looked at and not used: the preset `microsoft-graph-rate-limiting` (it only watches drives, shares and sites), and the Graph docs mocks in [pnp/proxy-samples `microsoft-graph-sandbox-mocks`](https://github.com/pnp/proxy-samples/tree/main/samples/microsoft-graph-sandbox-mocks) and [graph-mocks](https://github.com/waldekmastykarz/graph-mocks). Those are canned answers built from the Graph reference examples (the sandbox variant uses Graph Explorer's demo data). They have no throttling scenarios and are stateless. They could supply sample bodies for a fixture. I did not check whether they cover the contact folder endpoints.
