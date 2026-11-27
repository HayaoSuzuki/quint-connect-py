# Rust runner conformance fixtures

Generate `runner-conformance.json` by running the scenarios in
[`quint_conformance.qnt`](../quint_conformance.qnt). Each scenario supplies a
single ordered schedule of call requests and responses. The exporter reads the
generated ITF traces to extract each call's outcome, its event history, and the
file contents after all calls finish. It updates the fixture file if the
TypeScript and Rust evaluators produce identical JSON.

From the repository root, run the following commands with Python 3.10 or later
and Quint 0.34.0. The first command generates the JSON. The second checks that
both evaluators agree with each other and with the checked-in file.

```sh
python3 tools/export_quint_fixtures.py
python3 tools/export_quint_fixtures.py --check
```

Run `cargo test --lib conformance` to check the 17 cases against the Rust
implementation. Each test reads one case and supplies its responses to the
production runner. The tests compare the generation and replay event histories,
diagnostics, saved files, and remaining workspace files with the fixture JSON.

## Adapter inputs and outputs

The verification script starts the adapter once per case and writes one JSON
object to its standard input. The adapter can parse the input with
`serde_json` and must write one JSON object containing its result to standard
output. Send diagnostics to standard error. Verification fails if the adapter
exits with a nonzero status, produces invalid JSON, or differs from the expected
result.

```sh
python3 tools/export_quint_fixtures.py --adapter ./path/to/runner-fixture-adapter
```

The input fields are `schema_version` (`2`), `name`, `input_files`, and
`schedule`. Process the schedule array in order. Each entry has a `call_id`
and an `input`. A `Start` input starts the call. A `Respond` input supplies
the child process, file operation, or driver response the call is waiting for.
Keep the call available after `Start` so later entries can supply responses.
Calls in a case share the filesystem, including artifact destinations.

For a `ReplayPaths` request, use the paths in the order given. The list may
include repeated paths and paths that do not exist. A `RunQuint` request
supplies the CLI settings, seed input, artifact root, and selection paths for
the action and state. Read saved ITF bytes from `input_files` and generated ITF
bytes from the child process response.

The adapter's output has the fields in the case's `expected` object.

| Field | Contents |
| --- | --- |
| `calls` | Objects containing `call_id`, `events`, and `outcome`, sorted by ascending `call_id`. |
| `saved_files` | Paths and full byte contents of artifacts after all calls finish. |
| `remaining_workspace_files` | Paths and full byte contents of files left in workspaces after all calls finish. |

List `events` in the order they occur for the call. They include command
preparation, process handling, file reads, driver calls, artifact reservation
and saving, and cleanup. Use `Passed` or `Failed` for the final `outcome`.
A failure includes the diagnostic and any cleanup note.

In `artifactPreparationFailure`, the artifact root cannot be prepared. The
original mismatch retains its seed and records the preparation error. The
runner skips candidate reservation and cleans the workspace.

In `overlappingArtifactReservation`, two calls use the same seed and filename
and compete for the first candidate directory under the same artifact root.
Report a collision for a candidate that is already reserved. Use the
`ArtifactReservation` response for an available candidate. One call
continues copying after the other publishes its artifact and cleans up. The
comparison checks which artifact path each diagnostic refers to and whether
each artifact contains the original bytes.

In `waitFailureWithDeferredCleanup`, a `ChildIoFailed` response carries
`ExitUnconfirmed`. The following `WorkspaceCleanupWasDeferred` response
supplies the reason the adapter could not confirm exit and the bytes that
remain in the workspace. The comparison checks the wait failure diagnostic,
the workspace whose cleanup was deferred, and the files left there.

In `outputCollectionFailureAfterExitConfirmation`, the adapter also starts
with exit unconfirmed. `ChildExitWasConfirmed` confirms exit and supplies the
workspace bytes. The following `WorkspaceCleanup` completes cleanup. The
output collection failure remains the primary diagnostic.

In `nestedArgumentMutationMismatch`, `DriverApplyWithMutation.arguments`
contains the arguments after the driver's changes. Change the values inside
the arguments passed to the driver before returning `result`. The comparison
checks the changed values and the original arguments in the state mismatch
diagnostic.

Encode Quint variants as objects with `tag` and `value`. Use `null` for
variants without a payload. Encode paths as `SavedFile`, `WorkingFile`, or
`EvidenceFile`. Use zero-based position indices. Trace IDs identify files
independently of replay order.

Represent file contents and child process output as arrays of integers from
0 to 255. Use JSON strings for action names and each segment of a selection
path. Represent action arguments as JSON objects keyed by argument name.
Use ITF value encodings for argument values, expected states, and observed
states. Encode integers as decimal strings under `#bigint` and use ITF tags
for tuples, sets, and maps.

To sort set elements or map entries, serialize each element or entry as
compact JSON with sorted object keys and compare the resulting strings. The
verification script uses the same ordering. Sort file arrays by comparing
their paths in the same way. Event and byte arrays are compared in order.
