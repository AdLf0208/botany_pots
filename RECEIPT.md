# Package receipt — botanypots 0.2.2

This tag's archive is the file below. Earlier sections of `notes.md` and
`VALIDATION.md` describe earlier builds of this port; where a digest there differs,
**this receipt is the one that matches the release asset.**

| field | value |
|---|---|
| version | `0.2.2` |
| file | `botanypots.hmod` |
| bytes | 62,403 |
| sha256 | `f76388afda5f28434323247b9e95d237de925de741cc806f6d8a78839e7f23f9` |
| source | this tag — the tree here is the source that produced the archive |
| game | 26.3 |
| horizon | `0b14f8acfd97fa2c750e42795249dcc981178ca4` |
| horizon-mixins | `e59da9094f0c2fdda6c627fe9eff22dec6a906f0` |

## Verification of these exact bytes

`cargo test` 27 passed / 0 failed · `clippy --all-targets -- -D warnings` 0 warnings · `fmt --check` clean · two builds `cmp`-identical · `check` exit 0 · `fits --build 0b14f8a` `0b14f8a made for` exit 0 · `verify-sdk-package.py` 1/1 · launcher leg `PASS` + `EXIT:0`, control `EXIT:1`, `SELFTEST=1` `EXIT:1`, `SELFTEST=basic` `EXIT:1`, `check-e2e-logs --strict` 4/4
