# XM Agent Guidelines

## Development

```sh
mix deps.get
mix ci
```

## Scope

- Keep XM focused on a beautiful, generic XML DSL and Saxy-backed encoding.
- Do not add Astral-specific concepts to XM.
- Preserve XML escaping/encoding safety; never build XML with string concatenation.
- Do not publish, tag, or create a GitHub repository unless explicitly requested.
