defmodule Astro.Ephemeris.LoaderTest do
  # The ephemeris is loaded once, by the `:astro` application or by
  # `Astro.Supervisor` where an application supervises Astro itself. Not
  # async: it removes and replaces the loaded ephemeris.
  use ExUnit.Case, async: false

  alias Astro.Ephemeris.{Kernel, Loader}

  setup do
    saved = :persistent_term.get(Kernel.ephemeris_key())
    ephemeris = Application.get_env(:astro, :ephemeris)
    url = Application.get_env(:astro, :ephemeris_url)

    on_exit(fn ->
      :persistent_term.put(Kernel.ephemeris_key(), saved)
      restore_env(:ephemeris, ephemeris)
      restore_env(:ephemeris_url, url)
    end)

    %{kernel: saved}
  end

  defp restore_env(key, nil), do: Application.delete_env(:astro, key)
  defp restore_env(key, value), do: Application.put_env(:astro, key, value)

  test "an ephemeris loaded already is kept", %{kernel: kernel} do
    assert Loader.ensure_loaded() == :ok
    assert Kernel.ephemeris().id == kernel.id
  end

  test "an ephemeris not yet loaded is loaded", %{kernel: kernel} do
    :persistent_term.erase(Kernel.ephemeris_key())

    assert Loader.ensure_loaded() == :ok
    assert %Kernel{id: id} = Kernel.ephemeris()
    assert id != kernel.id
    assert %Geo.PointZ{} = Astro.sun_position_at(~D[2024-06-01])
  end

  test "an ephemeris that cannot be found is an error saying how to install it" do
    :persistent_term.erase(Kernel.ephemeris_key())

    missing =
      Path.join(System.tmp_dir!(), "astro-missing-#{System.unique_integer([:positive])}.bsp")

    Application.put_env(:astro, :ephemeris, missing)
    Application.put_env(:astro, :ephemeris_url, "http://127.0.0.1:9/de440s.bsp")

    assert {:error, message} = Loader.ensure_loaded()
    assert message =~ "could not load the JPL DE-series ephemeris"
    assert message =~ missing
    assert :persistent_term.get(Kernel.ephemeris_key(), nil) == nil
  end
end
