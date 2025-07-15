# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.ChangeTest do
  use Carbonite.APICase, async: true
  alias Carbonite.Change

  @json_module if Code.ensure_loaded?(JSON), do: JSON, else: Jason

  describe "JSON Encoder implementation" do
    test "Carbonite.Change can be encoded to JSON" do
      json =
        %Change{
          id: 1,
          op: :update,
          table_prefix: "default",
          table_name: "rabbits",
          table_pk: ["1"],
          data: %{"name" => "Jack"},
          changed: ["name"],
          changed_from: %{"name" => "Jane"}
        }
        |> @json_module.encode!()
        |> @json_module.decode!()

      assert json ==
               %{
                 "changed" => ["name"],
                 "changed_from" => %{"name" => "Jane"},
                 "data" => %{"name" => "Jack"},
                 "id" => 1,
                 "op" => "update",
                 "table_name" => "rabbits",
                 "table_pk" => ["1"],
                 "table_prefix" => "default"
               }
    end
  end
end
