# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Prefix do
  @moduledoc false

  # This module primarily exists to support dynamic from/join prefixes in Ecto until the next
  # Ecto version has been released.
  #
  # https://github.com/elixir-ecto/ecto/commit/0ab34faa734d0f010dc6ba031c9ebe469c8b1563
  #
  # Plan is to wait for a while after its release, than require Ecto 3.9.x at least and remove
  # the code in this file.

  defmacro default_prefix, do: "carbonite_default"

  defmacro from_with_prefix(from_expr, opts) do
    quote do
      unquote(from_expr)
      |> Ecto.Query.from()
      |> apply_carbonite_prefix_on_from_expr(unquote(opts))
    end
  end

  defmacro join_with_prefix(queryable, type, binding, join_expr, opts) do
    quote do
      unquote(queryable)
      |> Ecto.Query.join(unquote(type), unquote(binding), unquote(join_expr))
      |> apply_carbonite_prefix_on_join_expr(unquote(opts))
    end
  end

  @doc false
  @spec apply_carbonite_prefix_on_from_expr(Ecto.Query.t(), keyword) :: Ecto.Query.t()
  def apply_carbonite_prefix_on_from_expr(%{from: from} = queryable, opts) do
    # Inject the prefix into the FromExpr manually.
    %{queryable | from: apply_carbonite_prefix(from, opts)}
  end

  @doc false
  @spec apply_carbonite_prefix_on_join_expr(Ecto.Query.t(), keyword) :: Ecto.Query.t()
  def apply_carbonite_prefix_on_join_expr(%{joins: [join]} = queryable, opts) do
    # Inject the prefix into the JoinExpr manually.
    %{queryable | joins: [apply_carbonite_prefix(join, opts)]}
  end

  defp apply_carbonite_prefix(expr, opts) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    Map.put(expr, :prefix, to_string(carbonite_prefix))
  end
end
