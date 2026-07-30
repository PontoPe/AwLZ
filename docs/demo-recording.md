# Recording the AwLZ terminal demo

The reusable method comes from the sibling
[ProvenancePipeline recording guide](../../ProvenancePipeline/docs/demo-recording.md).
This repository keeps the same two artifacts:

- `docs/img/awlz-ci-readonly.cast` is the raw, auditable asciinema v2 stream;
- `docs/img/awlz-ci-readonly.gif` is the rendered portfolio artifact.

The driver is deliberately local and deterministic. It strictly validates the
sanitized IAM simulation evidence from C5, then shows one allowed read and one
explicitly denied write. It performs no AWS call and receives no credential,
account ID, ARN or external command.

Run on WSL/Linux:

```bash
make demo-record
```

`scripts/demo-record.sh`:

1. proves its deny regex with a fake ARN canary;
2. records through `asciinema --command` without an idle limit;
3. refuses promotion if the raw cast contains an account ID, ARN, credential,
   email, organization ID or SSO portal;
4. applies pacing only while rendering with `agg`; and
5. extracts a middle frame so the pixels can be inspected separately.

The canary never enters the recording. It exists only in the temporary
directory and confirms the audit would fail if sensitive AWS identifiers were
present.
