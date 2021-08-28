defmodule Carbonite.Postgrex.Xid8 do
  @moduledoc false

  # TODO: This will be obsolete with the next postgrex release, which will have Xid8 support.

  import Postgrex.BinaryUtils, warn: false
  use Postgrex.BinaryExtension, send: "xid8send"

  @int8_range -9_223_372_036_854_775_808..9_223_372_036_854_775_807

  def encode(_) do
    range = Macro.escape(@int8_range)

    quote location: :keep do
      int when is_integer(int) and int in unquote(range) ->
        <<8::int32, int::int64>>

      other ->
        raise DBConnection.EncodeError, Postgrex.Utils.encode_msg(other, unquote(range))
    end
  end

  def decode(_) do
    quote location: :keep do
      <<8::int32, int::int64>> -> int
    end
  end
end
