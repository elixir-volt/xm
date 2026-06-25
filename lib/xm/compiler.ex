defmodule XM.Compiler do
  @moduledoc """
  Compiles `XM` DSL blocks into quoted Saxy simple-form XML nodes.

  This module is intentionally separate from the runtime encoder API. Macro
  transformation stays here; XML node construction and encoding stay in `XM`.
  """

  @doc "Compile a DSL block into quoted node-list construction."
  @spec block(Macro.t()) :: Macro.t()
  def block(ast), do: block(ast, schema_prefixes(ast))

  defp block({:__block__, _meta, expressions}, prefixes) do
    expressions |> Enum.map(&expr(&1, prefixes)) |> list_ast()
  end

  defp block(expression, prefixes), do: list_ast([expr(expression, prefixes)])

  defp expr({:for, meta, args}, prefixes) do
    {clauses, [blocks]} = Enum.split(args, -1)
    {:for, meta, clauses ++ [transform_clauses(blocks, prefixes)]}
  end

  defp expr({:if, meta, [condition, clauses]}, prefixes) when is_list(clauses) do
    {:if, meta, [condition, transform_clauses(clauses, prefixes)]}
  end

  defp expr({:unless, meta, [condition, clauses]}, prefixes) when is_list(clauses) do
    {:unless, meta, [condition, transform_clauses(clauses, prefixes)]}
  end

  defp expr({:case, meta, [value, [do: clauses]]}, prefixes) do
    clauses =
      Enum.map(clauses, fn {:->, arrow_meta, [patterns, body]} ->
        {:->, arrow_meta, [patterns, block(body, prefixes)]}
      end)

    {:case, meta, [value, [do: clauses]]}
  end

  defp expr({:schema, _meta, [[do: schema_block]]}, _prefixes) do
    entries = schema_entries(schema_block)

    quote do
      XM.Schema.new(unquote(entries))
    end
  end

  defp expr({:cdata, _meta, [value]}, _prefixes) do
    quote do
      XM.cdata(unquote(value))
    end
  end

  defp expr({:text, _meta, [value]}, _prefixes) do
    quote do
      XM.text(unquote(value))
    end
  end

  defp expr({:comment, _meta, [value]}, _prefixes) do
    quote do
      XM.comment(unquote(value))
    end
  end

  defp expr({:tag, _meta, args}, prefixes) do
    {name, attrs, children} = dynamic_tag_parts(args, prefixes)

    quote do
      XM.element(unquote(name), unquote(attrs), unquote(children))
    end
  end

  defp expr({{:., _dot_meta, [{prefix, _prefix_meta, context}, local]}, _meta, args}, prefixes)
       when is_atom(prefix) and is_atom(local) and is_list(args) and context in [nil, Elixir] do
    if MapSet.member?(prefixes, prefix) do
      {attrs, children} = tag_parts(args, prefixes)

      quote do
        XM.element(XM.qname(unquote(prefix), unquote(local)), unquote(attrs), unquote(children))
      end
    else
      {{:., [], [{prefix, [], context}, local]}, [], args}
    end
  end

  defp expr({name, _meta, args}, prefixes) when is_atom(name) and is_list(args) do
    {attrs, children} = tag_parts(args, prefixes)

    quote do
      XM.element(unquote(Macro.escape(name)), unquote(attrs), unquote(children))
    end
  end

  defp expr(expression, _prefixes), do: expression

  defp transform_clauses(clauses, prefixes) do
    clauses
    |> Keyword.update!(:do, &block(&1, prefixes))
    |> transform_else_clause(prefixes)
  end

  defp transform_else_clause(clauses, prefixes) do
    if Keyword.has_key?(clauses, :else) do
      Keyword.update!(clauses, :else, &block(&1, prefixes))
    else
      clauses
    end
  end

  defp dynamic_tag_parts(args, prefixes) do
    {do_block, args} = pop_do_block(args)

    case args do
      [name, attrs] -> {name, attrs, children(do_block, [], prefixes)}
      [name] -> {name, [], children(do_block, [], prefixes)}
      _ -> raise ArgumentError, "tag/2 expects tag name, optional attrs, and optional do block"
    end
  end

  defp tag_parts(args, prefixes) do
    {do_block, args} = pop_do_block(args)

    attrs =
      case args do
        [attrs] when is_list(attrs) -> if Keyword.keyword?(attrs), do: attrs, else: []
        _ -> []
      end

    children =
      children(do_block, if(attrs != [] and match?([_], args), do: [], else: args), prefixes)

    {attrs, children}
  end

  defp children(nil, args, _prefixes), do: list_ast(args)
  defp children(do_block, _args, prefixes), do: block(do_block, prefixes)

  defp pop_do_block(args) do
    case Enum.split(args, -1) do
      {rest, [[do: block]]} -> {block, rest}
      _ -> {nil, args}
    end
  end

  defp schema_prefixes({:__block__, _meta, expressions}) do
    expressions
    |> Enum.flat_map(&schema_prefixes/1)
    |> MapSet.new()
  end

  defp schema_prefixes({:schema, _meta, [[do: block]]}), do: schema_block_prefixes(block)
  defp schema_prefixes(_expression), do: []

  defp schema_block_prefixes({:__block__, _meta, expressions}),
    do: Enum.flat_map(expressions, &schema_block_prefixes/1)

  defp schema_block_prefixes({:ns, _meta, [prefix | _args]}) when is_atom(prefix), do: [prefix]
  defp schema_block_prefixes(_expression), do: []

  defp schema_entries({:__block__, _meta, expressions}) do
    expressions |> Enum.map(&schema_entry/1) |> list_ast()
  end

  defp schema_entries(expression), do: list_ast([schema_entry(expression)])

  defp schema_entry({:default, _meta, args}) do
    {uri, opts} = schema_uri_opts!(args, :default)

    quote do
      {:default, unquote(uri), unquote(opts)}
    end
  end

  defp schema_entry({:ns, _meta, args}) do
    {prefix, uri, opts} = schema_prefix_uri_opts!(args)

    quote do
      {:ns, unquote(prefix), unquote(uri), unquote(opts)}
    end
  end

  defp schema_entry(other) do
    raise ArgumentError,
          "schema blocks support only default/1, default/2, ns/2, and ns/3 declarations, got: #{Macro.to_string(other)}"
  end

  defp schema_uri_opts!([uri], _kind), do: {uri, []}
  defp schema_uri_opts!([uri, opts], _kind) when is_list(opts), do: {uri, opts}

  defp schema_uri_opts!(args, kind) do
    raise ArgumentError,
          "#{kind}/1 expects a namespace URI and optional keyword options, got: #{inspect(args)}"
  end

  defp schema_prefix_uri_opts!([prefix, uri]), do: {prefix, uri, []}
  defp schema_prefix_uri_opts!([prefix, uri, opts]) when is_list(opts), do: {prefix, uri, opts}

  defp schema_prefix_uri_opts!(args) do
    raise ArgumentError,
          "ns/2 expects a prefix, namespace URI, and optional keyword options, got: #{inspect(args)}"
  end

  defp list_ast(items) do
    quote do
      [unquote_splicing(items)]
    end
  end
end
