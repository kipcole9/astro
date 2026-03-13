defmodule Astro.Ephemeris.Kernel do
  @moduledoc """
  Parses JPL DE-series binary SPK ephemeris files (DAF/SPK format).

  Supports Type 2 segments (Chebyshev position polynomials), which is the
  type used for planetary and lunar positions in DE440s and related files.

  ### Usage

      # This step is performed automatically at application start
      {:ok, kernel} = Astro.Ephemeris.Kernel.load("priv/de440s.bsp")

      # Moon wrt EMB
      {:ok, seg} = Astro.Ephemeris.Kernel.find_segment(301, 3)
      {x, y, z} = Astro.Ephemeris.Kernel.position(seg, dynamical_time)

  `dynamical_time` is TDB seconds past J2000.0 (2000-01-01T12:00:00 TT).
  Returned `{x, y, z}` are in km relative to the segment's centre body.

  ### Design notes

  The full file binary is stored inside the kernel struct so that
  `position/3` does not re-read the file on every call. For a 32 MB
  DE440s file this avoids ~thousands of disk reads per rise/set computation.

  ### DAF/SPK Type 2 format

  A DAF (Double Precision Array File) consists of 1024-byte records.
  Record 1 is the file header. Subsequent records form a comment area
  followed by a doubly-linked list of summary/name record pairs.

  Each segment descriptor (summary) contains:
    - ND=2 doubles: start_dt, end_dt (dynamical time — TDB seconds past J2000.0)
    - NI=6 integers packed as raw int32 bytes: target, centre, frame,
      data_type, start_addr, end_addr

  Addresses are 1-based word (8-byte double) indices into the whole file.

  A Type 2 segment's data area contains N Chebyshev records followed by
  4 metadata words [init_dt (dynamical time), intlen, rsize, n] at the very end.
  Each Chebyshev record has `rsize` doubles:
  ```
    [t_mid, t_half, cx_0..cx_d, cy_0..cy_d, cz_0..cz_d]
  ```
  where `d = degree = (rsize - 2) / 3 - 1`.

  """
  alias Astro.Math

  @record_size 1024
  @double_size 8
  # SPK always has ND=2, NI=6; summary = 5 doubles = 40 bytes
  @summary_bytes 40
  @ephemeris_key {Astro, :ephemeris}

  defstruct [:path, :endian, :data, :segments]

  @type t :: %__MODULE__{
          path: String.t(),
          endian: :little | :big,
          data: binary(),
          segments: [map()]
        }

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Loads and parses a JPL DE-series SPK binary ephemeris file.

  The entire file is read into memory and all Type 2 segment
  descriptors are extracted so that subsequent `position/2` calls
  do not require disk I/O.

  ### Arguments

  * `path` is the filesystem path to a DAF/SPK file
    (e.g. `"priv/de440s.bsp"`).

  ### Returns

  * `{:ok, kernel}` where `kernel` is an `Astro.Ephemeris.Kernel`
    struct containing the parsed segments and the raw binary data.

  * `{:error, reason}` if the file cannot be read or is not a
    valid DAF/SPK file.

  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, data} <- File.read(path),
         {:ok, endian} <- detect_endian(data),
         {:ok, fward} <- read_fward(data, endian) do
      segments = read_all_segments(data, fward, endian)
      {:ok, %__MODULE__{path: path, endian: endian, data: data, segments: segments}}
    end
  end

  @doc """
  Returns the loaded ephemeris kernel from `:persistent_term` storage.

  The kernel is loaded at application start by Astro.Application
  and stored under `ephemeris_key/0`.

  ### Returns

  * An `Astro.Ephemeris.Kernel` struct.

  """
  def ephemeris do
    :persistent_term.get(@ephemeris_key)
  end

  @doc false
  def ephemeris_key do
    @ephemeris_key
  end

  @doc """
  Finds the first segment matching `target` and `centre` NAIF IDs.

  If `dynamical_time` is provided, only segments whose time span
  covers the given instant are considered. If `nil` (the default),
  the first matching segment regardless of time span is returned.

  ### Arguments

  * `target` is the NAIF body ID of the target body
    (e.g. `301` for the Moon).

  * `centre` is the NAIF body ID of the centre body
    (e.g. `3` for the Earth–Moon Barycenter).

  * `dynamical_time` is TDB seconds past J2000.0, or `nil`
    to match any time span. Defaults to `nil`.

  ### Returns

  * `{:ok, segment}` where `segment` is a map describing the
    matching Type 2 segment.

  * `{:error, :not_found}` if no matching segment exists.

  """
  @spec find_segment(integer(), integer(), float() | nil) ::
          {:ok, map()} | {:error, :not_found}
  def find_segment(target, centre, dynamical_time \\ nil) do
    %__MODULE__{segments: segs} = ephemeris()

    match =
      Enum.find(segs, fn seg ->
        seg.target == target and seg.centre == centre and
          (is_nil(dynamical_time) or
             (dynamical_time >= seg.start_dt and dynamical_time <= seg.end_dt))
      end)

    case match do
      nil -> {:error, :not_found}
      seg -> {:ok, seg}
    end
  end

  @doc """
  Evaluates a Type 2 Chebyshev segment at the given dynamical time.

  Reads the appropriate Chebyshev record from the in-memory kernel
  data, normalizes the time argument to [-1, +1], and evaluates the
  polynomial for each Cartesian axis.

  ### Arguments

  * `segment` is a segment map as returned by `find_segment/3`.

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{x, y, z}` position in kilometers relative to the segment's
    centre body.

  """
  @spec position(map(), float()) :: {float(), float(), float()}
  def position(segment, dynamical_time) do
    %__MODULE__{data: data, endian: endian} = ephemeris()

    %{
      start_addr: start_addr,
      init_dt: init_dt,
      intlen: intlen,
      rsize: rsize,
      n_records: n_records,
      degree: degree
    } = segment

    # Identify which Chebyshev record covers `dynamical_time` (0-based index).
    idx = trunc((dynamical_time - init_dt) / intlen)
    idx = max(0, min(idx, n_records - 1))

    # Byte offset of this record in the file.
    # start_addr is a 1-based word index into the entire file.
    rec_byte = (start_addr - 1 + idx * rsize) * @double_size
    rec_size = rsize * @double_size
    rec_bin = binary_part(data, rec_byte, rec_size)

    # Parse record: t_mid, t_half, then (degree+1) coefficients per axis.
    t_mid = read_double(rec_bin, 0, endian)
    t_half = read_double(rec_bin, 1, endian)

    # Normalise time to [-1, +1].
    s = (dynamical_time - t_mid) / t_half

    n = degree + 1
    cx = read_doubles_range(rec_bin, 2, n, endian)
    cy = read_doubles_range(rec_bin, 2 + n, n, endian)
    cz = read_doubles_range(rec_bin, 2 + 2 * n, n, endian)

    {Math.evaluate_chebyshev(cx, s), Math.evaluate_chebyshev(cy, s),
     Math.evaluate_chebyshev(cz, s)}
  end

  # ── Binary parsing ───────────────────────────────────────────────────────────

  defp detect_endian(data) do
    case data do
      <<"DAF/SPK ", _::binary>> ->
        # ND is stored at bytes 8-11 as a 4-byte signed integer; for SPK it is 2.
        <<_::8-bytes, nd_le::little-signed-32, _::binary>> = data

        if nd_le == 2 do
          {:ok, :little}
        else
          <<_::8-bytes, nd_be::big-signed-32, _::binary>> = data
          if nd_be == 2, do: {:ok, :big}, else: {:error, :unrecognised_nd}
        end

      _ ->
        {:error, :not_daf_spk}
    end
  end

  defp read_fward(data, _endian) do
    # fward at bytes 76-79 (0-indexed), 4-byte little-endian (or big) integer.
    # For simplicity we already know endianness; use little for all modern files.
    <<_::76-bytes, fward::little-signed-32, _::binary>> = data
    {:ok, fward}
  end

  defp read_all_segments(data, fward, endian) do
    collect_summaries(data, fward, endian, [])
  end

  defp collect_summaries(_data, 0, _endian, acc), do: Enum.reverse(acc)

  defp collect_summaries(_data, rec, _endian, acc)
       when rec < 0, do: Enum.reverse(acc)

  defp collect_summaries(data, rec_num, endian, acc) do
    # Each summary record is exactly 1024 bytes.
    # Bytes 0-23: next (double), prev (double), nsum (double)
    # Bytes 24+: summaries, each @summary_bytes bytes wide.
    rec_offset = (rec_num - 1) * @record_size
    rec_bin = binary_part(data, rec_offset, @record_size)

    next = trunc(read_double(rec_bin, 0, endian))
    nsum = trunc(read_double(rec_bin, 2, endian))

    # Each summary starts at byte 24 (after the 3-double header), then every 40 bytes.
    new_segs =
      Enum.reduce(0..(nsum - 1), [], fn i, s_acc ->
        sum_offset = 3 * @double_size + i * @summary_bytes
        sum_bin = binary_part(rec_bin, sum_offset, @summary_bytes)

        case parse_summary(sum_bin, data, endian) do
          nil -> s_acc
          seg -> [seg | s_acc]
        end
      end)

    collect_summaries(data, next, endian, Enum.reverse(new_segs) ++ acc)
  end

  # Parses a single 40-byte summary binary into a segment map.
  # Layout (SPK, ND=2, NI=6):
  #   bytes  0- 7: start_dt  (double)
  #   bytes  8-15: end_dt    (double)
  #   bytes 16-19: target    (int32)
  #   bytes 20-23: centre    (int32)
  #   bytes 24-27: frame     (int32)
  #   bytes 28-31: data_type (int32)
  #   bytes 32-35: start_addr(int32)
  #   bytes 36-39: end_addr  (int32)
  defp parse_summary(sum_bin, data, endian) do
    start_dt = read_double(sum_bin, 0, endian)
    end_dt = read_double(sum_bin, 1, endian)
    target = read_int32(sum_bin, 16, endian)
    centre = read_int32(sum_bin, 20, endian)
    frame = read_int32(sum_bin, 24, endian)
    data_type = read_int32(sum_bin, 28, endian)
    start_addr = read_int32(sum_bin, 32, endian)
    end_addr = read_int32(sum_bin, 36, endian)

    if data_type != 2 do
      nil
    else
      # Type 2 metadata: last 4 doubles of the segment.
      # These are at absolute word indices end_addr-3, end_addr-2, end_addr-1, end_addr.
      # In bytes: starting at (end_addr - 4) * 8.
      meta_byte = (end_addr - 4) * @double_size
      meta_bin = binary_part(data, meta_byte, 4 * @double_size)

      init_dt = read_double(meta_bin, 0, endian)
      intlen = read_double(meta_bin, 1, endian)
      rsize = trunc(read_double(meta_bin, 2, endian))
      n_records = trunc(read_double(meta_bin, 3, endian))
      degree = div(rsize - 2, 3) - 1

      %{
        target: target,
        centre: centre,
        frame: frame,
        data_type: data_type,
        start_dt: start_dt,
        end_dt: end_dt,
        start_addr: start_addr,
        end_addr: end_addr,
        init_dt: init_dt,
        intlen: intlen,
        rsize: rsize,
        n_records: n_records,
        degree: degree
      }
    end
  end

  # ── Low-level binary reads ───────────────────────────────────────────────────

  # Read the nth double (0-based) from a binary.
  defp read_double(bin, n, endian) do
    offset = n * @double_size

    case endian do
      :little ->
        <<_::binary-size(^offset), v::little-float-64, _::binary>> = bin
        v

      :big ->
        <<_::binary-size(^offset), v::big-float-64, _::binary>> = bin
        v
    end
  end

  # Read `count` consecutive doubles starting at word index `start_n` (0-based).
  defp read_doubles_range(bin, start_n, count, endian) do
    for i <- start_n..(start_n + count - 1) do
      read_double(bin, i, endian)
    end
  end

  # Read a signed 32-bit integer at `byte_offset` from a binary.
  defp read_int32(bin, byte_offset, endian) do
    case endian do
      :little ->
        <<_::binary-size(^byte_offset), v::little-signed-32, _::binary>> = bin
        v

      :big ->
        <<_::binary-size(^byte_offset), v::big-signed-32, _::binary>> = bin
        v
    end
  end
end
