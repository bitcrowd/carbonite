# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.Helper do
  @moduledoc false

  import Ecto.Migration, only: [execute: 1]

  # Removes surrounding and consecutive whitespace from SQL to improve readability in console.
  @spec squish(String.t()) :: String.t()
  def squish(statement) do
    statement
    |> String.replace(~r/[[:space:]]+/, " ")
    |> String.trim()
  end

  # Removes surrounding and consecutive whitespace from SQL to improve readability in console.
  @spec squish_and_execute(String.t()) :: :ok
  def squish_and_execute(statement) do
    statement
    |> squish()
    |> execute()
  end

  # Joins a list of atoms/strings to a `{'bar', 'foo', ...}` (ordered) SQL array expression.
  @spec column_list(nil | [atom() | String.t()]) :: String.t()
  def column_list(nil), do: "'{}'"
  def column_list(value), do: "'{#{do_column_list(value)}}'"

  defp do_column_list(value) do
    value
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.map_join(", ", &"\"#{&1}\"")
  end

  # Locks a table in exclusive mode for constraint modifications & co.
  @spec lock_table(binary(), binary()) :: :ok
  def lock_table(prefix, table) do
    squish_and_execute("LOCK TABLE #{prefix}.#{table} IN EXCLUSIVE MODE;")
  end
end
