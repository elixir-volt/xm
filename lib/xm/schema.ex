defmodule XM.Schema do
  @moduledoc """
  Declarative XML namespace and XSD schema metadata.

  `XM.Schema` values are produced by the `schema do ... end` DSL inside an
  `XM.document/2` block. They are not rendered as XML elements. Instead, they
  inject namespace declaration attributes into the document root and provide XSD
  locations for optional validation.
  """

  @xsi_namespace "http://www.w3.org/2001/XMLSchema-instance"

  @type namespace :: %{prefix: String.t() | nil, uri: String.t(), location: String.t() | nil}
  @type t :: %__MODULE__{namespaces: [namespace()]}

  defstruct namespaces: []

  @doc "Build schema metadata from DSL entries."
  @spec new(list()) :: t()
  def new(entries) when is_list(entries) do
    %__MODULE__{namespaces: Enum.map(entries, &namespace!/1)}
  end

  @doc "Return XML attributes that should be injected into the root element."
  @spec attributes(t()) :: [{String.t(), String.t()}]
  def attributes(%__MODULE__{} = schema) do
    namespace_attrs = Enum.map(schema.namespaces, &namespace_attribute/1)

    case schema_locations(schema) do
      [] ->
        namespace_attrs

      locations ->
        namespace_attrs ++ [{"xmlns:xsi", @xsi_namespace}, {"xsi:schemaLocation", locations}]
    end
  end

  @doc "Return schema location paths/URLs declared by the schema metadata."
  @spec locations(t()) :: [String.t()]
  def locations(%__MODULE__{} = schema) do
    schema.namespaces
    |> Enum.map(& &1.location)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Return true when schema metadata declares at least one XSD location."
  @spec has_locations?(t()) :: boolean()
  def has_locations?(%__MODULE__{} = schema), do: locations(schema) != []

  defp namespace!({:default, uri, opts}) do
    %{prefix: nil, uri: to_text!(uri), location: location(opts)}
  end

  defp namespace!({:ns, prefix, uri, opts}) do
    %{prefix: to_name!(prefix), uri: to_text!(uri), location: location(opts)}
  end

  defp namespace!(entry) do
    raise XM.Error,
      reason: :invalid_schema,
      message: "invalid schema declaration #{inspect(entry)}"
  end

  defp namespace_attribute(%{prefix: nil, uri: uri}), do: {"xmlns", uri}
  defp namespace_attribute(%{prefix: prefix, uri: uri}), do: {XM.qname(:xmlns, prefix), uri}

  defp schema_locations(schema) do
    schema.namespaces
    |> Enum.filter(& &1.location)
    |> Enum.flat_map(&[&1.uri, &1.location])
    |> Enum.join(" ")
    |> case do
      "" -> []
      locations -> locations
    end
  end

  defp location(opts), do: opts |> Keyword.get(:location) |> maybe_text()

  defp maybe_text(nil), do: nil
  defp maybe_text(value), do: to_text!(value)

  defp to_name!(value) when is_atom(value), do: Atom.to_string(value)
  defp to_name!(value) when is_binary(value), do: value

  defp to_name!(value) do
    raise XM.Error,
      reason: :invalid_name,
      message: "XML namespace prefixes must be atoms or strings, got: #{inspect(value)}"
  end

  defp to_text!(value), do: XM.__to_text__!(value)
end
