defmodule Carbonite.Prefix do
  @moduledoc false

  @doc false
  defmacro default_prefix, do: "carbonite_default"

  defmacro __using__(_opts) do
    quote do
      @schema_prefix "carbonite_default"
    end
  end
end
