defmodule Carbonite.Migrations do
  @moduledoc """
  Functions to setup version trails in migrations.
  """

  use Ecto.Migration

  @type prefix_option :: {:prefix, binary()}
  @type migration_option :: prefix_option() | {:version, non_neg_integer()}

  @current_version 1

  @default_prefix "public"

  @doc """
  Install/migrate the Carbonite tables and related functionality.
  """
  @spec up([migration_option()]) :: :ok
  def up(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    version = Keyword.get(opts, :version, @current_version)
    initial = migrated_version(repo(), prefix)

    if initial < version do
      change(prefix, (initial + 1)..version, :up)
    end
  end

  @spec down([migration_option()]) :: :ok
  def down(opts \\ []) when is_list(opts) do
    # TODO
    :ok
  end

  # ------------------ BEGIN SHAMELESSLY STOLEN CODE FROM OBAN ---------------------

  defp migrated_version(repo, prefix) do
    query = """
    SELECT description
    FROM pg_class
    LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
    LEFT JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_class.relname = 'carbonite_transactions'
    AND pg_namespace.nspname = '#{prefix}'
    """

    case repo.query!(query) do
      %{rows: [[version]]} when is_binary(version) -> String.to_integer(version)
      %{rows: []} -> 0
    end
  end

  defp change(prefix, range, direction) do
    for index <- range do
      pad_idx = String.pad_leading(to_string(index), 2, "0")

      [__MODULE__, "V#{pad_idx}"]
      |> Module.concat()
      |> apply(direction, [prefix])
    end

    case direction do
      :up -> record_version(prefix, Enum.max(range))
      :down -> record_version(prefix, Enum.min(range) - 1)
    end
  end

  defp record_version(_prefix, 0), do: :ok

  defp record_version(prefix, version) do
    execute("COMMENT ON TABLE #{prefix}.carbonite_transactions IS '#{version}'")
  end

  # ------------------- END SHAMELESSLY STOLEN CODE FROM OBAN -----------------------

  @spec install_on_table(binary(), [prefix_option()]) :: :ok
  def install_on_table(schema, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    except = Keyword.get(opts, :except, [])

    except =
      except
      |> Enum.map(&"\"#{&1}\"")
      |> Enum.join(",")

    execute("""
    CREATE TRIGGER carbonite_changes_trg
    AFTER INSERT OR UPDATE OR DELETE
    ON #{prefix}.#{schema}
    FOR EACH ROW
    EXECUTE PROCEDURE #{prefix}.carbonite_capture_changes('{#{except}}');
    """)

    :ok
  end

  @spec drop_from_table(binary(), [prefix_option()]) :: :ok
  def drop_from_table(schema, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)

    execute("DROP TRIGGER carbonite_changes_trg ON #{prefix}.#{schema};")

    :ok
  end
end
