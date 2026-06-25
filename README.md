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
- Dynamic/namespaced tag names with `tag/2` and `qname/2`.
- Namespace declarations with `xmlns/1`, `xmlns/2`, and declarative `schema do ... end` metadata.
- Dotted namespace calls such as `image.image do ... end` for declared prefixes.
- Optional XSD validation through `XM.validate!/2` or compile-time global config.
- Idiomatic `%XM.Error{}` exceptions for invalid documents, names, attributes, text, or schema validation.
- `for`, `if`, `unless`, and `case` inside XML blocks.
- Explicit `text/1`, `comment/1`, and `cdata/1` nodes.
- Binary rendering with `render/2` and iodata rendering with `render_iodata/2`.
- Iodata-first pipelines with `tree do ... end |> render_iodata()`.
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

### Namespaces and schema declarations

`schema do ... end` is document metadata, not an XML element. XM injects namespace declarations into the document root and renders XSD locations as `xsi:schemaLocation`.

```elixir
import XM

xml =
  document do
    schema do
      default "http://www.sitemaps.org/schemas/sitemap/0.9",
        location: "priv/schemas/sitemap.xsd"

      ns :image, "http://www.google.com/schemas/sitemap-image/1.1",
        location: "priv/schemas/sitemap-image.xsd"
    end

    urlset do
      url do
        loc "https://example.com/"

        image.image do
          image.loc "https://example.com/image.jpg"
        end
      end
    end
  end
```

### Namespaced or dynamic tags

```elixir
import XM

tree do
  tag qname(:media, :thumbnail), [xmlns(:media, "https://example.com/media"), url: "https://example.com/image.png"]
end
```

### Iodata rendering

`document do ... end` is the convenience API for producing a binary XML document.
For iodata, build nodes with `tree do ... end` and render explicitly:

```elixir
import XM

iodata =
  tree do
    feed do
      title "Hello"
    end
  end
  |> XM.render_iodata()

IO.iodata_to_binary(iodata)
```

This mirrors common Elixir conventions: keep binary and iodata rendering as separate functions instead of overloading a single `render/2` option.

### XSD validation

Use `XM.validate!/2` explicitly:

```elixir
XM.validate!(xml)
XM.validate!(xml, schema: "priv/schemas/sitemap.xsd")
XM.validate!(xml, schemas: ["priv/schemas/sitemap.xsd", "priv/schemas/sitemap-image.xsd"])
```

Without explicit `:schema`/`:schemas`, XM reads schema locations from the parsed root element's `xsi:schemaLocation` or `xsi:noNamespaceSchemaLocation` attributes.

To validate every `document do ... end`, enable XM's global compile-time configuration before modules using `document/2` are compiled:

```elixir
config :xm, validate: true
```

The option is captured when the `document do ... end` macro expands. It is intentionally global; there is no per-document `validate:` option. If validation is enabled and the document does not declare schema locations, XM raises `%XM.Error{reason: :missing_schema}`.

## License

MIT © 2026 Danila Poyarkov
