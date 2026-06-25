# XM

Beautiful Elixir DSL for building XML documents, backed by Saxy for escaping and encoding.

```elixir
import XM

document do
  urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
    for page <- pages do
      url do
        loc site_url <> page.path
        lastmod page.date
      end
    end
  end
end
```

XM is intentionally tiny: local calls become XML elements, keyword arguments become attributes, and normal Elixir expressions still work.

## Features

- Nested XML elements with Elixir `do/end` syntax.
- Attributes via keyword lists or maps.
- Dynamic/namespaced tag names with `tag/2`.
- `for`, `if`, `unless`, and `case` inside XML blocks.
- Explicit `text/1`, `comment/1`, and `cdata/1` nodes.
- Binary rendering with `render/2` and iodata rendering with `render_iodata/2`.
- Saxy-backed escaping and XML encoding.

## Installation

```elixir
def deps do
  [
    {:xm, "~> 0.1.0"}
  ]
end
```

## Examples

### Sitemap

```elixir
import XM

pages = [
  %{path: "/", date: ~D[2026-06-25]},
  %{path: "/about/", date: ~D[2026-06-25]}
]

xml =
  document do
    urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
      for page <- pages do
        url do
          loc "https://example.com" <> page.path
          lastmod page.date
        end
      end
    end
  end
```

### Atom entry with CDATA

```elixir
import XM

document do
  entry do
    title "Hello"

    content type: "html" do
      cdata "<p>Hello from XML</p>"
    end
  end
end
```

### Namespaced or dynamic tags

```elixir
import XM

tree do
  tag "media:thumbnail", url: "https://example.com/image.png"
end
```

## License

MIT © 2026 Danila Poyarkov
