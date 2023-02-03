defmodule Carbonite.Schema do
  @moduledoc false

  defmacro default_prefix, do: "carbonite_default"

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
