defmodule Astro.Time do
  @moduledoc """
  Calculations converting between geometry and time

  All public functions use degrees as their input
  parameters

  Time is a fraction of a day after UTC

  """

  alias Astro.Location

  @julian_day_jan_1_2000 2_451_545.0
  @julian_days_per_century 36525.0

  @doc """
  Calculates the time zone from a longitude
  in degrees

  ## Arguments

  * `lng` is a longitude in degrees

  ## Returns

  * `time` as a fraction of a day after UTC

  """
  def offset(lng) do
    lng / 360.0
  end

  def utc_from_local(local_time, %Location{offset: offset}) do
    local_time - offset
  end

  def local_from_utc(utc_time, %Location{offset: offset}) do
    utc_time + offset
  end

  def standard_from_utc(utc_time, %Location{zone: zone}) do
    utc_time + zone
  end

  def utc_from_standard(standard_time, %Location{zone: zone}) do
    standard_time - zone
  end

  def julian_centuries_from_julian_day(julian_day) do
    (julian_day - @julian_day_jan_1_2000) / @julian_days_per_century
  end

  def julian_day_from_julian_centuries(julian_centuries) do
    julian_centuries * @julian_days_per_century + @julian_day_jan_1_2000
  end

  # def julian_day_from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
  #   (1461 * (year + 4800 + (month - 14) / 12) / 4 +
  #     367 * (month - 2 - 12 * ((month - 14) / 12)) / 12 -
  #     3 * ((year + 4900 + (month - 14.0) / 12) / 100) / 4 + day - 32075)
  #     |> IO.inspect(label: "Julian day")
  # end

  def julian_day_from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    {year, month} =
      if month in 1..2 do
        {year - 1, month + 12}
      else
        {year, month}
      end

    # That is if the date is Jan or Feb then the date is the 13th or
    # 14th month of the preceding year for calculation purposes.
    # If the date is on the Gregorian calendar (after 14 Oct 1582) then:

    a = trunc(year / 100)
    b = 2 - a + trunc(a / 4)

    trunc(365.25 * (year + 4716)) + trunc(30.6001 * (month + 1)) + day + b - 1524.5
  end

  def julian_day_from_date(%{year: year, month: month, day: day, calendar: Cldr.Calendar.Gregorian}) do
    julian_day_from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO})
  end

  def ajd(date) do
    julian_day_from_date(date)
  end

  def mjd(date) do
    ajd(date) - 2_400_000.5
  end

  def to_datetime(time_of_day, %{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    {hours, minutes, seconds} = to_hms(time_of_day)
    {:ok, datetime} = NaiveDateTime.new(year, month, day, hours, minutes, seconds, 0)
    datetime
  end

  def to_hms(time_of_day) do
    hours = trunc(time_of_day)
    minutes = (time_of_day - hours) * 60.0
    seconds = (minutes - trunc(minutes)) * 60.0

    minutes = trunc(minutes)
    seconds = trunc(seconds)

    {hours, minutes, seconds}
  end

end
