defmodule Astro.SunriseSunsetTest do
  use ExUnit.Case

  @sydney {151.20666584, -33.8559799094}

  for [day, sunrise_hour, sunrise_minute, _, _] <- Astro.TestData.sunrise("sydney") do
    test "Sunrise on December #{day} 2019 for Sydney, Australia" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunrise} = Astro.sunrise(@sydney, date)
      assert sunrise.day == unquote(day)
      assert sunrise.hour == unquote(sunrise_hour)
      assert_in_delta sunrise.minute, unquote(sunrise_minute), 1
    end
  end

  for [day, _, _, sunset_hour, sunset_minute] <- Astro.TestData.sunrise("sydney") do
    test "Sunset on December #{day} 2019 for Sydney, Australia" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunset} = Astro.sunset(@sydney, date)
      assert sunset.day == unquote(day)
      assert sunset.hour == unquote(sunset_hour) + 12
      assert_in_delta sunset.minute, unquote(sunset_minute), 1
    end
  end

  @moscow {37.6173, 55.7558}

  for [day, sunrise_hour, sunrise_minute, _, _] <- Astro.TestData.sunrise("moscow") do
    test "Sunrise on December #{day} 2019 for Moscow, Russia" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunrise} = Astro.sunrise(@moscow, date)
      assert sunrise.day == unquote(day)
      assert sunrise.hour == unquote(sunrise_hour)
      assert_in_delta sunrise.minute, unquote(sunrise_minute), 1
    end
  end

  for [day, _, _, sunset_hour, sunset_minute] <- Astro.TestData.sunrise("moscow") do
    test "Sunset on December #{day} 2019 for Moscow, Russia" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunset} = Astro.sunset(@moscow, date)
      assert sunset.day == unquote(day)
      assert sunset.hour == unquote(sunset_hour) + 12
      assert_in_delta sunset.minute, unquote(sunset_minute), 1
    end
  end

  @nyc {-74.0060, 40.7128}

  for [day, sunrise_hour, sunrise_minute, _, _] <- Astro.TestData.sunrise("nyc") do
    test "Sunrise on December #{day} 2019 for NY, NY" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunrise} = Astro.sunrise(@nyc, date)
      assert sunrise.day == unquote(day)
      assert sunrise.hour == unquote(sunrise_hour)
      assert_in_delta sunrise.minute, unquote(sunrise_minute), 1
    end
  end

  for [day, _, _, sunset_hour, sunset_minute] <- Astro.TestData.sunrise("nyc") do
    test "Sunset on December #{day} 2019 for NY, NY" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunset} = Astro.sunset(@nyc, date)
      assert sunset.day == unquote(day)
      assert sunset.hour == unquote(sunset_hour) + 12
      assert_in_delta sunset.minute, unquote(sunset_minute), 1
    end
  end

  @sao_paulo {-46.6396, -23.5558}

  for [day, sunrise_hour, sunrise_minute, _, _] <- Astro.TestData.sunrise("sao_paulo") do
    test "Sunrise on December #{day} 2019 for São Paulo, Brazil" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunrise} = Astro.sunrise(@sao_paulo, date)
      assert sunrise.day == unquote(day)
      assert sunrise.hour == unquote(sunrise_hour)
      assert_in_delta sunrise.minute, unquote(sunrise_minute), 1
    end
  end

  for [day, _, _, sunset_hour, sunset_minute] <- Astro.TestData.sunrise("sao_paulo") do
    test "Sunset on December #{day} 2019 for São Paulo, Brazil" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunset} = Astro.sunset(@sao_paulo, date)
      assert sunset.day == unquote(day)
      assert sunset.hour == unquote(sunset_hour) + 12
      assert_in_delta sunset.minute, unquote(sunset_minute), 1
    end
  end

  @beijing {116.4074, 39.9042}

  for [day, sunrise_hour, sunrise_minute, _, _] <- Astro.TestData.sunrise("beijing") do
    test "Sunrise on December #{day} 2019 for Beijing, China" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunrise} = Astro.sunrise(@beijing, date)
      assert sunrise.day == unquote(day)
      assert sunrise.hour == unquote(sunrise_hour)
      assert_in_delta sunrise.minute, unquote(sunrise_minute), 1
    end
  end

  for [day, _, _, sunset_hour, sunset_minute] <- Astro.TestData.sunrise("beijing") do
    test "Sunset on December #{day} 2019 for Beijing, China" do
      {:ok, date} = Date.new(2019, 12, unquote(day))
      {:ok, sunset} = Astro.sunset(@beijing, date)
      assert sunset.day == unquote(day)
      assert sunset.hour == unquote(sunset_hour) + 12
      assert_in_delta sunset.minute, unquote(sunset_minute), 1
    end
  end
end
