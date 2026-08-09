defmodule Astro.Ephemeris.Subset do
  @moduledoc """
  Extracts a smaller DAF/SPK ephemeris kernel from a larger one.

  JPL's `de440s.bsp` is ~31 MB because it carries all planetary
  barycenters over 1849–2150. `Astro` uses only four segments — Moon
  and Earth relative to the Earth–Moon Barycenter, and Sun and EMB
  relative to the Solar System Barycenter — so the remainder can be
  discarded.

  Extraction is **lossless** within the retained window: the original
  Chebyshev coefficients are copied verbatim, so positions computed
  from a subset file are bit-for-bit identical to those computed from
  the source file. No refitting is performed.

  ### What drives the file size

  Body selection alone saves less than expected. The Moon and Earth
  segments are the two largest in the file (degree-12 polynomials on
  4-day intervals), together ~17 MB, while the eight discarded
  planetary barycenters use 32-day intervals and cost little. The
  dominant lever is the **time window** — after body selection the
  cost is roughly 42 KB per year of coverage.

  A second saving comes from omitting the Earth→EMB segment. By the
  definition of the barycenter it is an exact scalar multiple of the
  Moon→EMB segment:

      Earth→EMB = -(1 / EMRAT) x Moon→EMB

  where `EMRAT` is the Earth/Moon mass ratio (81.3005682214972154 for
  DE440). `Astro.Ephemeris.Kernel` reconstructs the segment on demand
  when it is absent, so omitting it halves the payload at a cost of
  one multiplication per evaluation.

  ### Compatibility

  The output is a valid DAF/SPK file. The source file record is copied
  intact — preserving the format identifier, the FTP validation string
  and the binary format marker — so the result is readable by other
  SPICE implementations (CSPICE, `jplephem`, Astropy) and not only by
  this library.

  """

  @record_size 1024
  @double_size 8
  @summary_bytes 40

  # Words per record: 1024 / 8.
  @words_per_record 128

  # Output layout: record 1 file record, record 2 summaries, record 3 names,
  # record 4 onward element data. Addresses are 1-based word indices.
  @first_data_word 3 * @words_per_record + 1

  @doc """
  Extracts selected segments and a time window from a DAF/SPK file.

  ### Arguments

  * `source_path` is the path of the DAF/SPK file to read, typically a
    JPL `de440s.bsp`.

  * `dest_path` is the path of the subset file to write.

  ### Options

  * `:bodies` is a list of `{target_id, centre_id}` NAIF body ID pairs
    to retain. Defaults to the four segments `Astro` requires,
    excluding Earth→EMB, which is reconstructed at runtime.

  * `:from` is the first instant the subset must cover, as a `Date`,
    `DateTime` or integer year. Defaults to the source file's start.

  * `:to` is the last instant the subset must cover, in the same forms
    as `:from`. Defaults to the source file's end.

  ### Returns

  * `{:ok, report}` where `report` is a map containing `:path`,
    `:bytes`, `:segments` (a list of retained `{target, centre}`
    pairs) and `:coverage` (a `{first_year, last_year}` tuple).

  * `{:error, reason}` if the source cannot be read or parsed, or if a
    requested body pair or time window is not present in the source.

  ### Examples

      # Retain Astro's segments over 1900-2100
      Astro.Ephemeris.Subset.extract(
        "de440s.bsp",
        "priv/de440s-astro.bsp",
        from: 1900,
        to: 2100
      )

  """
  @spec extract(Path.t(), Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract(source_path, dest_path, options \\ []) do
    with {:ok, source} <- File.read(source_path),
         {:ok, endian} <- detect_endian(source),
         {:ok, summaries} <- read_summaries(source, endian),
         {:ok, selected} <- select_bodies(summaries, options),
         {:ok, sliced} <- slice_window(selected, source, endian, options) do
      binary = build(source, sliced, endian)

      case File.write(dest_path, binary) do
        :ok ->
          {:ok,
           %{
             path: dest_path,
             bytes: byte_size(binary),
             segments: Enum.map(sliced, &{&1.target, &1.centre}),
             coverage: coverage(sliced)
           }}

        {:error, reason} ->
          {:error, {:write_failed, dest_path, reason}}
      end
    end
  end

  @doc """
  Returns the default set of `{target_id, centre_id}` pairs retained by
  `extract/3`.

  Earth→EMB (399→3) is deliberately absent; it is reconstructed from
  Moon→EMB at runtime. See the module documentation.

  ### Returns

  * A list of `{target_id, centre_id}` tuples.

  ### Examples

      iex> Astro.Ephemeris.Subset.default_bodies()
      [{301, 3}, {10, 0}, {3, 0}]

  """
  @spec default_bodies() :: [{integer(), integer()}]
  def default_bodies do
    [{301, 3}, {10, 0}, {3, 0}]
  end

  # ── Source parsing ──────────────────────────────────────────────────────────

  defp detect_endian(<<"DAF/SPK ", nd_le::little-signed-32, _::binary>> = data) do
    if nd_le == 2 do
      {:ok, :little}
    else
      <<_::8-bytes, nd_be::big-signed-32, _::binary>> = data
      if nd_be == 2, do: {:ok, :big}, else: {:error, :unrecognised_nd}
    end
  end

  defp detect_endian(_data) do
    {:error, :not_daf_spk}
  end

  # Walks the doubly-linked list of summary records, pairing each summary with
  # the name held in the record that immediately follows it.
  defp read_summaries(data, endian) do
    fward = read_int32(data, 76, endian)
    {:ok, collect(data, fward, endian, [])}
  end

  defp collect(_data, rec_num, _endian, acc) when rec_num <= 0, do: Enum.reverse(acc)

  defp collect(data, rec_num, endian, acc) do
    summary_bin = record(data, rec_num)
    name_bin = record(data, rec_num + 1)

    next = trunc(read_double(summary_bin, 0, endian))
    nsum = trunc(read_double(summary_bin, 2, endian))

    parsed =
      for i <- 0..(nsum - 1)//1 do
        offset = 3 * @double_size + i * @summary_bytes

        parse_summary(binary_part(summary_bin, offset, @summary_bytes), endian)
        |> Map.put(:name, binary_part(name_bin, i * @summary_bytes, @summary_bytes))
      end

    collect(data, next, endian, Enum.reverse(parsed) ++ acc)
  end

  defp parse_summary(bin, endian) do
    %{
      start_dt: read_double(bin, 0, endian),
      end_dt: read_double(bin, 1, endian),
      target: read_int32(bin, 16, endian),
      centre: read_int32(bin, 20, endian),
      frame: read_int32(bin, 24, endian),
      data_type: read_int32(bin, 28, endian),
      start_addr: read_int32(bin, 32, endian),
      end_addr: read_int32(bin, 36, endian)
    }
  end

  defp record(data, rec_num) do
    binary_part(data, (rec_num - 1) * @record_size, @record_size)
  end

  # ── Selection ───────────────────────────────────────────────────────────────

  defp select_bodies(summaries, options) do
    wanted = Keyword.get(options, :bodies, default_bodies())

    selected =
      Enum.map(wanted, fn {target, centre} ->
        Enum.find(summaries, &(&1.target == target and &1.centre == centre))
      end)

    case Enum.find_index(selected, &is_nil/1) do
      nil ->
        unsupported = Enum.find(selected, &(&1.data_type != 2))

        if unsupported do
          {:error, {:unsupported_data_type, unsupported.data_type}}
        else
          {:ok, selected}
        end

      index ->
        {:error, {:segment_not_found, Enum.at(wanted, index)}}
    end
  end

  # ── Time window ─────────────────────────────────────────────────────────────

  defp slice_window(segments, data, endian, options) do
    from = options |> Keyword.get(:from) |> to_dynamical_time(:min)
    to = options |> Keyword.get(:to) |> to_dynamical_time(:max)

    Enum.reduce_while(segments, {:ok, []}, fn segment, {:ok, acc} ->
      case slice(segment, data, endian, from, to) do
        {:ok, sliced} -> {:cont, {:ok, [sliced | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sliced} -> {:ok, Enum.reverse(sliced)}
      error -> error
    end
  end

  # A Type 2 segment stores n records of rsize doubles followed by four
  # metadata doubles [init_dt, intlen, rsize, n]. Truncating in time is a
  # matter of keeping records first..last and rewriting that metadata.
  defp slice(segment, data, endian, from, to) do
    meta_offset = (segment.end_addr - 4) * @double_size
    meta = binary_part(data, meta_offset, 4 * @double_size)

    init_dt = read_double(meta, 0, endian)
    intlen = read_double(meta, 1, endian)
    rsize = trunc(read_double(meta, 2, endian))
    count = trunc(read_double(meta, 3, endian))

    # Reject a window that does not intersect the segment at all. Clamping
    # alone would silently pin both ends to the same boundary record and yield
    # a one-record segment covering a period that was never asked for.
    if to < init_dt or from > init_dt + count * intlen do
      {:error, {:empty_window, {segment.target, segment.centre}}}
    else
      first = clamp(floor_div(from - init_dt, intlen), 0, count - 1)
      last = clamp(floor_div(to - init_dt, intlen), 0, count - 1)
      kept = last - first + 1
      new_init_dt = init_dt + first * intlen

      coefficients =
        binary_part(
          data,
          (segment.start_addr - 1 + first * rsize) * @double_size,
          kept * rsize * @double_size
        )

      payload =
        coefficients <>
          double(new_init_dt, endian) <>
          double(intlen, endian) <>
          double(rsize * 1.0, endian) <>
          double(kept * 1.0, endian)

      {:ok,
       %{
         segment
         | start_dt: new_init_dt,
           end_dt: new_init_dt + kept * intlen
       }
       |> Map.put(:payload, payload)}
    end
  end

  # Record boundaries are 4 to 32 days wide depending on the body, so the
  # window is widened to the enclosing boundary rather than narrowed. Leap
  # seconds are immaterial at this granularity.
  defp to_dynamical_time(nil, :min), do: -1.0e18
  defp to_dynamical_time(nil, :max), do: 1.0e18

  defp to_dynamical_time(year, bound) when is_integer(year) do
    month_day = if bound == :min, do: {1, 1}, else: {12, 31}
    {month, day} = month_day
    {:ok, date} = Date.new(year, month, day)
    to_dynamical_time(date, bound)
  end

  defp to_dynamical_time(%Date{} = date, bound) do
    {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])
    to_dynamical_time(DateTime.from_naive!(naive, "Etc/UTC"), bound)
  end

  defp to_dynamical_time(%DateTime{} = date_time, _bound) do
    DateTime.diff(date_time, ~U[2000-01-01 12:00:00Z]) * 1.0
  end

  defp floor_div(numerator, denominator), do: Float.floor(numerator / denominator) |> trunc()

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  # ── Output construction ─────────────────────────────────────────────────────

  defp build(source, segments, endian) do
    {payloads, _} =
      Enum.map_reduce(segments, @first_data_word, fn segment, word ->
        words = div(byte_size(segment.payload), @double_size)

        entry = %{
          segment
          | start_addr: word,
            end_addr: word + words - 1
        }

        {entry, word + words}
      end)

    free =
      @first_data_word + div(IO.iodata_length(Enum.map(payloads, & &1.payload)), @double_size)

    IO.iodata_to_binary([
      file_record(source, free, endian),
      summary_record(payloads, endian),
      name_record(payloads),
      Enum.map(payloads, & &1.payload)
    ])
  end

  # Copy the source file record verbatim so that the format identifier, the
  # binary format marker and the FTP validation string survive, then patch the
  # three record pointers and stamp an informative internal file name.
  defp file_record(source, free, endian) do
    original = binary_part(source, 0, @record_size)
    name = String.pad_trailing("ASTRO SUBSET OF DE-SERIES SPK", 60)

    <<head::binary-size(16), _name::binary-size(60), _fward::binary-size(4),
      _bward::binary-size(4), _free::binary-size(4), tail::binary>> = original

    head <>
      name <>
      int32(2, endian) <>
      int32(2, endian) <>
      int32(free, endian) <>
      tail
  end

  defp summary_record(segments, endian) do
    header =
      double(0.0, endian) <> double(0.0, endian) <> double(length(segments) * 1.0, endian)

    summaries =
      Enum.map(segments, fn segment ->
        double(segment.start_dt, endian) <>
          double(segment.end_dt, endian) <>
          int32(segment.target, endian) <>
          int32(segment.centre, endian) <>
          int32(segment.frame, endian) <>
          int32(segment.data_type, endian) <>
          int32(segment.start_addr, endian) <>
          int32(segment.end_addr, endian)
      end)

    pad(IO.iodata_to_binary([header | summaries]), 0)
  end

  defp name_record(segments) do
    segments
    |> Enum.map(& &1.name)
    |> IO.iodata_to_binary()
    |> pad(?\s)
  end

  defp pad(binary, byte) do
    binary <> :binary.copy(<<byte>>, @record_size - byte_size(binary))
  end

  defp coverage(segments) do
    first = segments |> Enum.map(& &1.start_dt) |> Enum.max()
    last = segments |> Enum.map(& &1.end_dt) |> Enum.min()
    {year_of(first), year_of(last)}
  end

  defp year_of(dynamical_time) do
    ~U[2000-01-01 12:00:00Z] |> DateTime.add(trunc(dynamical_time), :second) |> Map.get(:year)
  end

  # ── Binary primitives ───────────────────────────────────────────────────────

  defp double(value, :little), do: <<value::little-float-64>>
  defp double(value, :big), do: <<value::big-float-64>>

  defp int32(value, :little), do: <<value::little-signed-32>>
  defp int32(value, :big), do: <<value::big-signed-32>>

  defp read_double(bin, index, endian) do
    offset = index * @double_size

    case endian do
      :little ->
        <<_::binary-size(^offset), value::little-float-64, _::binary>> = bin
        value

      :big ->
        <<_::binary-size(^offset), value::big-float-64, _::binary>> = bin
        value
    end
  end

  defp read_int32(bin, offset, endian) do
    case endian do
      :little ->
        <<_::binary-size(^offset), value::little-signed-32, _::binary>> = bin
        value

      :big ->
        <<_::binary-size(^offset), value::big-signed-32, _::binary>> = bin
        value
    end
  end
end
