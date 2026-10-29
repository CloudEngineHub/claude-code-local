<!-- Drop-in for README.md: replaces the 16 GB and under-16 GB rows of the
     "What you need" table and adds a short section after it. Not linked from
     the docs site (excluded in mkdocs.yml). -->

Rows for the model table in "What you need":

```markdown
| **Under 16 GB** (8 GB) | 🟡 Qwen 3.5 2B, 8-bit. Reads images, 16K context, server peaks at 4.2 GB. [Small Macs](docs/SMALL-MACS.md) |
| **16 GB** (MacBook Air, base models) | 🟡 Qwen 3.5 4B, bf16. Reads images, 16K context, server peaks at 10.6 GB. [Small Macs](docs/SMALL-MACS.md) |
```

Section to add after the table:

```markdown
### 💻 On an 8 GB or 16 GB Mac?

`setup.sh` sees it and sets up the small-Mac tier for you: a model that reads files, edits them,
runs commands and looks at images, with the context capped to what your Mac can hold.

| Your Mac | Model | Server memory, peak | Speed (M4 Pro) |
|---|---|:---:|:---:|
| 16 GB | Qwen 3.5 4B, bf16 | 10.6 GB | 22 tok/s |
| 8 GB | Qwen 3.5 2B, 8-bit | 4.2 GB | 92 tok/s |

Both passed our Claude Code test (read a file, fix a bug with Edit, run a script, describe an
image). Keep requests to one clear step at a time. Measured numbers, settings and limits:
[docs/SMALL-MACS.md](docs/SMALL-MACS.md). Running one? Tell us how it goes in
[#57](https://github.com/nicedreamzapp/claude-code-local/issues/57).
```
