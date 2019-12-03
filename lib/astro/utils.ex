defmodule Astro.Utils do
  import Astro.Guards

  @radians_to_degrees 180.0 / :math.pi()

  def to_degrees(radians) do
    radians * @radians_to_degrees
  end

  def to_radians(degrees) do
    degrees / @radians_to_degrees
  end

  @doc """
  Calculates the modulo of a number (integer, float).

  Note that this function uses `floored division` whereas the builtin `rem`
  function uses `truncated division`. See `Decimal.rem/2` if you want a
  `truncated division` function for Decimals that will return the same value as
  the BIF `rem/2` but in Decimal form.

  See [Wikipedia](https://en.wikipedia.org/wiki/Modulo_operation) for an
  explanation of the difference.

  ## Examples

      iex> Cldr.Math.mod(1234.0, 5)
      4.0

      iex> Cldr.Math.mod(Decimal.new("1234.456"), 5)
      #Decimal<4.456>

      iex> Cldr.Math.mod(Decimal.new("123.456"), Decimal.new("3.4"))
      #Decimal<1.056>

      iex> Cldr.Math.mod Decimal.new("123.456"), 3.4
      #Decimal<1.056>

  """
  @spec mod(number, number) :: number

  def mod(number, modulus) when is_float(number) and is_number(modulus) do
    number - Float.floor(number / modulus) * modulus
  end

  def mod(number, modulus) when is_integer(number) and is_integer(modulus) do
    modulo =
      number
      |> Integer.floor_div(modulus)
      |> Kernel.*(modulus)

    number - modulo
  end

  def mod(number, modulus) when is_integer(number) and is_number(modulus) do
    modulo =
      number
      |> Kernel./(modulus)
      |> Float.floor()
      |> Kernel.*(modulus)

    number - modulo
  end

  @doc """
  Returns the remainder and dividend of two numbers.
  """
  @spec div_mod(number, number) :: {number, number}

  def div_mod(n1, n2) when is_integer(n1) and is_integer(n2) do
    div = div(n1, n2)
    mod = n2 - div * n2
    {div, mod}
  end

  def div_mod(n1, n2) when is_number(n1) and is_number(n2) do
    div = n1 / n2
    mod = n2 - div * n2
    {div, mod}
  end

  def normalize_location({lng, lat, alt}) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    %Geo.PointZ{coordinates: {lng, lat, alt}}
  end

  def normalize_location({lng, lat}) when is_lat(lat) and is_lng(lng) do
    %Geo.PointZ{coordinates: {lng, lat, 0.0}}
  end

  def normalize_location(%Geo.Point{coordinates: {lng, lat}}) when is_lat(lat) and is_lng(lng) do
    %Geo.PointZ{coordinates: {lng, lat, 0.0}}
  end
end
