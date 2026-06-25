defmodule XM do
  require Record

  Record.defrecordp(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))

  Record.defrecordp(
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @moduledoc """
  Beautiful Elixir DSL for building XML documents.

  XM turns Elixir syntax into Saxy simple-form XML nodes, then delegates
  escaping and encoding to Saxy. It is useful for feeds, sitemaps, service
  integrations, and any code that needs XML without string concatenation.

  ## Supported syntax

    * local calls become XML elements: `url do ... end`, `loc "..."`
    * keyword arguments become attributes: `link href: "/feed.xml", rel: "self"`
    * `tag/2` builds dynamic or namespaced names that are awkward as atoms
    * `qname/2` builds qualified names such as `"media:thumbnail"`
    * `xmlns/1` and `xmlns/2` build namespace declaration attributes
    * `schema do ... end` declares root namespaces and XSD locations
    * dotted namespace calls such as `media.thumbnail` work for declared prefixes
    * `XM.validate!/2` validates XML against declared or explicit XSD files
    * `config :xm, validate: true` validates every `document do ... end`
    * `for`, `if`, `unless`, and `case` work inside XML blocks
    * `text/1`, `comment/1`, and `cdata/1` create explicit XML node kinds
    * remote calls, variables, operators, and normal expressions remain Elixir

  ## Examples

      import XM

      document do
        urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
          url do
            loc "https://example.com/"
            lastmod Date.utc_today()
          end
        end
      end

      tree do
        tag qname(:media, :thumbnail), [xmlns(:media, "https://example.com/media"), url: image_url]
      end

  `document/2` requires exactly one root element and returns a binary. Use
  `tree/1` with `render_iodata/2` when you want iodata, or when building
  fragments to embed in a larger document.
  """

  @type attribute :: {String.t(), String.t()}
  @type xml_node ::
          Saxy.XML.element()
          | Saxy.XML.cdata()
          | Saxy.XML.comment()
          | Saxy.XML.characters()
          | Saxy.XML.ref()
          | Saxy.XML.processing_instruction()
  @type prolog :: Saxy.Prolog.t() | keyword() | nil

  @doc """
  Build and encode an XML document as a binary.

  The document macro reads `config :xm, validate: true` when the macro expands.
  If enabled, the rendered document is passed through `validate!/2`. Validation
  is intentionally global; there is no per-document validation option.
  """
  defmacro document(opts \\ [], do: block) do
    validate? = Application.get_env(:xm, :validate, false)

    quote do
      xml =
        unquote(__MODULE__).render(
          unquote(__MODULE__).nodes(unquote(XM.Compiler.block(block))),
          unquote(opts)
        )

      if unquote(validate?) do
        unquote(__MODULE__).validate!(xml)
      else
        xml
      end
    end
  end

  @doc "Build XML nodes without encoding them."
  defmacro tree(do: block) do
    quote do
      unquote(__MODULE__).nodes(unquote(XM.Compiler.block(block)))
    end
  end

  @doc "Encode XML nodes through Saxy and return a binary."
  @spec render(xml_node() | [xml_node()], prolog()) :: String.t()
  def render(nodes, prolog \\ [version: "1.0", encoding: "UTF-8"]) do
    {root, _schemas} = root_node!(nodes)
    Saxy.encode!(root, prolog)
  end

  @doc """
  Encode XML nodes through Saxy and return iodata.

  Use this with `tree/1` for iodata-first pipelines:

      tree do
        feed do
          title "Hello"
        end
      end
      |> XM.render_iodata()
  """
  @spec render_iodata(xml_node() | [xml_node()], prolog()) :: iodata()
  def render_iodata(nodes, prolog \\ [version: "1.0", encoding: "UTF-8"]) do
    {root, _schemas} = root_node!(nodes)
    Saxy.encode_to_iodata!(root, prolog)
  end

  @doc """
  Validate XML against XSD schema locations.

  By default, schema locations are read from parsed root attributes
  (`xsi:schemaLocation` or `xsi:noNamespaceSchemaLocation`). Pass `:schema` or
  `:schemas` to validate against explicit local XSD paths instead. Returns the
  original XML binary on success and raises `XM.Error` on failure.
  """
  @spec validate!(String.t(), keyword()) :: String.t()
  def validate!(xml, opts \\ []) when is_binary(xml) do
    {root, _rest} = :xmerl_scan.string(String.to_charlist(xml))
    schemas = validation_schemas!(root, opts)

    case process_schemas(schemas) do
      {:ok, state} ->
        case :xmerl_xsd.validate(root, state) do
          {:error, reason} -> raise_validation_error(reason)
          {_validated, _state} -> xml
        end

      error ->
        raise_validation_error(error)
    end
  end

  @doc "Build an XML element node."
  @spec element(atom() | String.t(), keyword() | map(), term()) :: Saxy.XML.element()
  def element(name, attrs \\ [], children \\ []) do
    Saxy.XML.element(xml_name!(name), attributes!(attrs), nodes(children))
  end

  @doc "Build a qualified XML name, such as `\"media:thumbnail\"`."
  @spec qname(atom() | String.t(), atom() | String.t()) :: String.t()
  def qname(prefix, local), do: xml_name!(prefix) <> ":" <> xml_name!(local)

  @doc "Build a default namespace declaration attribute."
  @spec xmlns(term()) :: attribute()
  def xmlns(uri), do: {"xmlns", __to_text__!(uri)}

  @doc "Build a prefixed namespace declaration attribute."
  @spec xmlns(atom() | String.t(), term()) :: attribute()
  def xmlns(prefix, uri), do: {qname(:xmlns, prefix), __to_text__!(uri)}

  @doc "Build a CDATA node."
  @spec cdata(term()) :: Saxy.XML.cdata()
  def cdata(value), do: Saxy.XML.cdata(__to_text__!(value))

  @doc "Build a text node."
  @spec text(term()) :: Saxy.XML.characters()
  def text(value), do: Saxy.XML.characters(__to_text__!(value))

  @doc "Build a comment node."
  @spec comment(term()) :: Saxy.XML.comment()
  def comment(value), do: Saxy.XML.comment(__to_text__!(value))

  @doc "Normalize nested XML nodes and scalar content."
  @spec nodes(term()) :: [term()]
  def nodes(value) when is_list(value),
    do: value |> Enum.flat_map(&nodes/1) |> Enum.reject(&is_nil/1)

  def nodes(nil), do: []
  def nodes(%XM.Schema{} = schema), do: [schema]
  def nodes({:characters, _value} = node), do: [node]
  def nodes({:cdata, _value} = node), do: [node]
  def nodes({:comment, _value} = node), do: [node]
  def nodes({:reference, _value} = node), do: [node]
  def nodes({:processing_instruction, _name, _instruction} = node), do: [node]

  def nodes({name, attrs, children}) when is_list(attrs) and is_list(children),
    do: [element(name, attrs, children)]

  def nodes(value), do: [text(value)]

  defp root_node!(value) do
    value
    |> nodes()
    |> split_schemas()
    |> root!()
  end

  defp split_schemas(nodes) do
    Enum.split_with(nodes, &match?(%XM.Schema{}, &1))
  end

  defp root!({schemas, [root]}), do: {inject_schema_attrs(root, schemas), schemas}

  defp root!({_schemas, []}) do
    raise XM.Error,
      reason: :empty_document,
      message: "XML document requires a root element; use tree/1 for empty fragments"
  end

  defp root!({_schemas, nodes}) do
    raise XM.Error,
      reason: :multiple_roots,
      message:
        "XML document requires exactly one root element, got #{length(nodes)} roots; use tree/1 for fragments"
  end

  defp inject_schema_attrs(root, []), do: root

  defp inject_schema_attrs({name, attrs, children}, schemas) do
    schema_attrs = schemas |> Enum.flat_map(&XM.Schema.attributes/1) |> Enum.uniq_by(&elem(&1, 0))
    {name, merge_attrs(schema_attrs, attrs), children}
  end

  defp merge_attrs(schema_attrs, attrs) do
    existing = MapSet.new(attrs, &elem(&1, 0))
    Enum.reject(schema_attrs, &(elem(&1, 0) in existing)) ++ attrs
  end

  defp validation_schemas!(root, opts) do
    opts
    |> explicit_schemas()
    |> case do
      [] -> declared_schema_locations(root)
      schemas -> schemas
    end
    |> case do
      [] ->
        raise XM.Error,
          reason: :missing_schema,
          message: "XML validation requires schema declarations or a :schema option"

      schemas ->
        schemas
    end
  end

  defp explicit_schemas(opts) do
    schemas =
      opts
      |> Keyword.get(:schemas, [])
      |> List.wrap()
      |> Enum.flat_map(&schema_locations/1)

    case schemas do
      [] ->
        opts
        |> Keyword.get(:schema)
        |> List.wrap()
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&__to_text__!/1)

      schemas ->
        schemas
    end
  end

  defp declared_schema_locations(root) do
    root
    |> xmlElement(:attributes)
    |> Enum.flat_map(&schema_locations_from_attribute/1)
  end

  defp schema_locations_from_attribute(attribute) do
    attribute
    |> xmlAttribute(:name)
    |> schema_locations_from_attribute_name(xmlAttribute(attribute, :value))
  end

  defp schema_locations_from_attribute_name(:"xsi:schemaLocation", value) do
    value
    |> to_string()
    |> schema_location_paths!()
  end

  defp schema_locations_from_attribute_name(:"xsi:noNamespaceSchemaLocation", value) do
    value
    |> to_string()
    |> String.split()
  end

  defp schema_locations_from_attribute_name(_name, _value), do: []

  defp schema_location_paths!(value) do
    parts = String.split(value)

    if rem(length(parts), 2) == 0 do
      parts
      |> Enum.chunk_every(2)
      |> Enum.map(fn [_namespace, location] -> location end)
    else
      raise XM.Error,
        reason: :invalid_schema,
        message:
          "xsi:schemaLocation must contain namespace/location pairs, got: #{inspect(value)}"
    end
  end

  defp raise_validation_error(reason) do
    raise XM.Error,
      reason: :schema_validation_failed,
      message: "XML schema validation failed: #{inspect(reason)}"
  end

  defp process_schemas([schema]), do: :xmerl_xsd.process_schema(String.to_charlist(schema))

  defp process_schemas(schemas) do
    schemas
    |> Enum.map(&{nil, String.to_charlist(&1)})
    |> :xmerl_xsd.process_schemas()
  end

  defp schema_locations(%XM.Schema{} = schema), do: XM.Schema.locations(schema)
  defp schema_locations(schema), do: [__to_text__!(schema)]

  defp attributes!(attrs) when is_map(attrs), do: attrs |> Map.to_list() |> attributes!()

  defp attributes!(attrs) when is_list(attrs) do
    if Enum.all?(attrs, &attribute?/1) do
      Enum.map(attrs, fn {key, value} -> {xml_name!(key), __to_text__!(value)} end)
    else
      raise XM.Error,
        reason: :invalid_attributes,
        message:
          "XML attributes must be a map or a list of {name, value} pairs, got: #{inspect(attrs)}"
    end
  end

  defp attributes!(attrs) do
    raise XM.Error,
      reason: :invalid_attributes,
      message:
        "XML attributes must be a map or a list of {name, value} pairs, got: #{inspect(attrs)}"
  end

  defp attribute?({key, _value}) when is_atom(key) or is_binary(key), do: true
  defp attribute?(_attribute), do: false

  defp xml_name!(name) when is_atom(name), do: name |> Atom.to_string() |> validate_name!()
  defp xml_name!(name) when is_binary(name), do: validate_name!(name)

  defp xml_name!(name) do
    raise XM.Error,
      reason: :invalid_name,
      message: "XML names must be atoms or strings, got: #{inspect(name)}"
  end

  defp validate_name!(name) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.-]*(?::[A-Za-z_][A-Za-z0-9_.-]*)?$/, name) do
      name
    else
      raise XM.Error,
        reason: :invalid_name,
        message: "invalid XML name #{inspect(name)}"
    end
  end

  @doc false
  @spec __to_text__!(term()) :: String.t()
  def __to_text__!(value) do
    case String.Chars.impl_for(value) do
      nil ->
        raise XM.Error,
          reason: :invalid_text,
          message: "cannot convert #{inspect(value)} to XML text"

      protocol ->
        protocol.to_string(value)
    end
  end
end
