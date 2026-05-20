defmodule Astro.Ephemeris.DownloaderTest do
  use ExUnit.Case, async: false

  alias Astro.Ephemeris.Downloader

  import ExUnit.CaptureLog

  setup do
    saved_ephemeris = Application.get_env(:astro, :ephemeris)
    saved_url = Application.get_env(:astro, :ephemeris_url)

    on_exit(fn ->
      restore_env(:ephemeris, saved_ephemeris)
      restore_env(:ephemeris_url, saved_url)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:astro, key)
  defp restore_env(key, value), do: Application.put_env(:astro, key, value)

  defp unique_tmp(name) do
    Path.join(System.tmp_dir!(), "astro-#{name}-#{System.unique_integer([:positive])}")
  end

  describe "ephemeris_path/0" do
    test "returns the configured :ephemeris path when set" do
      Application.put_env(:astro, :ephemeris, "/custom/de440s.bsp")
      assert Downloader.ephemeris_path() == "/custom/de440s.bsp"
    end

    test "returns the priv path when :ephemeris is unset and the file exists in priv" do
      Application.delete_env(:astro, :ephemeris)
      path = Downloader.ephemeris_path()

      assert String.ends_with?(path, "de440s.bsp")
      assert File.exists?(path), "expected priv/de440s.bsp to be present in the test environment"
    end
  end

  describe "ensure_ephemeris/1 when the file is present" do
    test "returns {:ok, path} and logs that no download is required" do
      path = Downloader.ephemeris_path()

      log =
        capture_log(fn ->
          assert {:ok, ^path} = Downloader.ensure_ephemeris(path)
        end)

      assert log =~ "Ephemeris file present at #{path}"
      assert log =~ "no download required"
    end
  end

  describe "ensure_ephemeris/1 when the file is missing" do
    test "logs 'not found, will download' and proceeds to download" do
      missing_dir = unique_tmp("missing")
      missing_path = Path.join(missing_dir, "de440s.bsp")

      Application.put_env(:astro, :ephemeris_url, "http://127.0.0.1:1/de440s.bsp")

      log =
        capture_log(fn ->
          assert {:error, _reason} = Downloader.ensure_ephemeris(missing_path)
        end)

      assert log =~ "Ephemeris file not found at #{missing_path}"
      assert log =~ "will download"

      File.rm_rf!(missing_dir)
    end
  end

  describe "download/1 directory creation" do
    test "logs and creates the target directory when it does not exist" do
      dir = unique_tmp("create-dir")
      path = Path.join(dir, "de440s.bsp")

      refute File.exists?(dir)

      Application.put_env(:astro, :ephemeris_url, "http://127.0.0.1:1/de440s.bsp")

      log =
        capture_log(fn ->
          assert {:error, _reason} = Downloader.download(path)
        end)

      assert log =~ "Creating ephemeris cache directory #{dir}"
      assert File.dir?(dir)

      File.rm_rf!(dir)
    end

    test "does not log a creation message when the target directory already exists" do
      dir = unique_tmp("existing-dir")
      File.mkdir_p!(dir)
      path = Path.join(dir, "de440s.bsp")

      Application.put_env(:astro, :ephemeris_url, "http://127.0.0.1:1/de440s.bsp")

      log =
        capture_log(fn ->
          assert {:error, _reason} = Downloader.download(path)
        end)

      refute log =~ "Creating ephemeris cache directory"

      File.rm_rf!(dir)
    end

    test "returns {:error, {:cache_dir_unwritable, ...}} and logs error when mkdir fails" do
      blocker = unique_tmp("blocker")
      File.write!(blocker, "")

      bad_dir = Path.join(blocker, "subdir")
      bad_path = Path.join(bad_dir, "de440s.bsp")

      log =
        capture_log(fn ->
          assert {:error, {:cache_dir_unwritable, ^bad_dir, _reason}} =
                   Downloader.download(bad_path)
        end)

      assert log =~ "Could not create ephemeris cache directory #{bad_dir}"
      assert log =~ "Set `config :astro, ephemeris:"

      File.rm!(blocker)
    end
  end

  describe "download/1 network failures" do
    setup do
      dir = unique_tmp("dl")
      File.mkdir_p!(dir)
      path = Path.join(dir, "de440s.bsp")

      on_exit(fn -> File.rm_rf!(dir) end)

      %{dir: dir, path: path}
    end

    test "logs download start with URL and destination", %{path: path} do
      url = "http://127.0.0.1:1/de440s.bsp"
      Application.put_env(:astro, :ephemeris_url, url)

      log =
        capture_log(fn ->
          assert {:error, _reason} = Downloader.download(path)
        end)

      assert log =~ "Downloading ephemeris"
      assert log =~ url
      assert log =~ path
    end

    test "logs an error and returns {:error, reason} when the connection fails", %{path: path} do
      url = "http://127.0.0.1:1/de440s.bsp"
      Application.put_env(:astro, :ephemeris_url, url)

      log =
        capture_log(fn ->
          assert {:error, _reason} = Downloader.download(path)
        end)

      assert log =~ "[error]"
      assert log =~ "Ephemeris download from #{url} failed"
    end

    test "removes any partial file on failure", %{path: path} do
      Application.put_env(:astro, :ephemeris_url, "http://127.0.0.1:1/de440s.bsp")

      capture_log(fn ->
        assert {:error, _reason} = Downloader.download(path)
      end)

      refute File.exists?(path), "partial download file should be removed on failure"
    end
  end
end
