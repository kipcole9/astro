defmodule Astro.Ephemeris.KernelRecordCacheTest do
  # The last decoded Chebyshev record of each segment is kept in the calling
  # process and reused. A position must be the same whether its record was
  # reused or decoded afresh, and a kernel put in place of another must never
  # be answered from the other's records.
  use ExUnit.Case, async: false

  alias Astro.Ephemeris.Kernel

  @sun 10
  @ssb 0
  @moon 301
  @earth 399
  @emb 3

  @day 86_400.0

  setup do
    saved = :persistent_term.get(Kernel.ephemeris_key())
    on_exit(fn -> :persistent_term.put(Kernel.ephemeris_key(), saved) end)
    %{kernel: saved}
  end

  test "a position is the same from a reused record as from a fresh decode" do
    # Times in an order that moves within records, between neighbouring
    # records and across years, for the Sun, the Moon and the Earth (whose
    # segment is rebuilt from the Moon's in the bundled kernel).
    times =
      for step <- [0.01, 0.5, 3.7, 40.0, 200.0], i <- 0..60 do
        Float.round(:math.sin(i) * 20_000.0) * @day + i * step * @day
      end

    for {target, centre} <- [{@sun, @ssb}, {@moon, @emb}, {@earth, @emb}], dt <- times do
      {:ok, segment} = Kernel.find_segment(target, centre, dt)
      reused = Kernel.position(segment, dt)
      clear_records()
      assert Kernel.position(segment, dt) == reused, "#{target} at #{dt}"
    end
  end

  test "a kernel put in place of another is not answered from its records", %{kernel: kernel} do
    dt = 1_000.0 * @day
    {:ok, segment} = Kernel.find_segment(@sun, @ssb, dt)
    {x, _y, _z} = Kernel.position(segment, dt)
    assert x != 0.0

    # The same segments, with the coefficients of the record that covers
    # `dt` set to zero, so a position read from this kernel is the origin.
    :persistent_term.put(Kernel.ephemeris_key(), zero_record(kernel, segment, dt))
    assert Kernel.position(segment, dt) == {0.0, 0.0, 0.0}

    :persistent_term.put(Kernel.ephemeris_key(), kernel)
    assert {^x, _y, _z} = Kernel.position(segment, dt)
  end

  defp zero_record(kernel, segment, dt) do
    %{start_addr: start_addr, init_dt: init_dt, intlen: intlen, rsize: rsize} = segment
    idx = trunc((dt - init_dt) / intlen)

    # The record's midpoint and half-width are kept; its coefficients follow.
    coefficients_byte = (start_addr - 1 + idx * rsize) * 8 + 16
    coefficients_size = (rsize - 2) * 8

    <<before::binary-size(^coefficients_byte), _::binary-size(^coefficients_size), rest::binary>> =
      kernel.data

    data = <<before::binary, 0::size(coefficients_size * 8), rest::binary>>
    %Kernel{kernel | id: make_ref(), data: data}
  end

  defp clear_records do
    for {{Kernel, :record, _address} = key, _record} <- Process.get(), do: Process.delete(key)
  end
end
