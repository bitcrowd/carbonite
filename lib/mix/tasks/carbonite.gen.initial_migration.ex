defmodule Mix.Tasks.Carbonite.Gen.InitialMigration do
  use Mix.Task

  import Macro, only: [camelize: 1, underscore: 1]
  import Mix.Generator
  import Mix.Ecto, except: [migrations_path: 1]
  import Ecto.Migrator, only: [migrations_path: 1]

  @shortdoc "Generates the initial migration to install Carbonite data structures"

  @moduledoc """
  Generates a sample migration that runs all migrations currently contained within Carbonite.
  """

  @doc false
  @dialyzer {:no_return, run: 1}

  def run(args) do
    no_umbrella!("carbonite.gen.initial_migration")
    repos = parse_repo(args)
    name = "install_carbonite"

    Enum.each(repos, fn repo ->
      ensure_repo(repo, args)
      path = Path.relative_to(migrations_path(repo), Mix.Project.app_path())
      file = Path.join(path, "#{timestamp()}_#{underscore(name)}.exs")
      create_directory(path)

      assigns = [mod: Module.concat([repo, Migrations, camelize(name)])]

      create_file(file, migration_template(assigns))
    end)
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i), do: i |> to_string() |> String.pad_leading(2, "0")

  embed_template(:migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration

    def up do
      # If you like to install Carbonite's tables into a different schema, add the
      # carbonite_prefix option.
      #
      #    Carbonite.Migrations.up(1, carbonite_prefix: "carbonite_other")

      <%= for i <- Carbonite.Migrations.initial_patch()..Carbonite.Migrations.current_patch() do %>Carbonite.Migrations.up(<%= i %>)
      <% end %>
      # Install a trigger for a table:
      #
      #    Carbonite.Migrations.create_trigger("rabbits")
      #    Carbonite.Migrations.create_trigger("rabbits", prefix: "lagomorpha")
      #    Carbonite.Migrations.create_trigger("rabbits", carbonite_prefix: "carbonite_other")

      # Configure trigger options:
      #
      #    Carbonite.Migrations.put_trigger_option("rabbits", :primary_key_columns, ["compound", "key"])
      #    Carbonite.Migrations.put_trigger_option("rabbits", :excluded_columns, ["private"])
      #    Carbonite.Migrations.put_trigger_option("rabbits", :filtered_columns, ["private"])
      #    Carbonite.Migrations.put_trigger_option("rabbits", :mode, :ignore)

    end

    def down do
      # Remove trigger from a table:
      #
      #    Carbonite.Migrations.drop_trigger("rabbits")
      #    Carbonite.Migrations.drop_trigger("rabbits", prefix: "lagomorpha")
      #    Carbonite.Migrations.drop_trigger("rabbits", carbonite_prefix: "carbonite_other")

      # Make sure to apply the same carbonite_prefix option here.
      <%= for i <- Carbonite.Migrations.current_patch()..Carbonite.Migrations.initial_patch() do %>Carbonite.Migrations.down(<%= i %>)
      <% end %>
    end
  end
  """)
end
