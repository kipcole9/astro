defmodule Astro.Math do
  @moduledoc false

  import Kernel, except: [min: 2, max: 2, ceil: 1, floor: 1]
  alias Astro.Time

  @radians_to_degrees 180.0 / :math.pi()
  @au_to_km 149_597_870.7
  @au_to_m 149_597_870.7 * 1_000

  defmacro to_degrees(radians) do
    radians_to_degrees = @radians_to_degrees

    quote do
      unquote(radians) * unquote(radians_to_degrees)
    end
  end

  defmacro to_radians(degrees) do
    radians_to_degrees = @radians_to_degrees

    quote do
      unquote(degrees) / unquote(radians_to_degrees)
    end
  end

  def au_to_km(au) do
    au * @au_to_km
  end

  def au_to_m(au) do
    au * @au_to_m
  end

  def m_to_au(m) do
    m / @au_to_m
  end

  def degrees(degrees) do
    mod(degrees, 360.0)
  end

  defmacro mt(x) do
    quote do
      unquote(x)
    end
  end

  defmacro deg(x) do
    quote do
      unquote(x)
    end
  end

  defmacro angle(d, m, s) do
    angle = d + (m + s / Time.seconds_per_minute()) / Time.minutes_per_hour()

    quote do
      unquote(angle)
    end
  end

  defmacro degrees_minutes_seconds(d, m, s) do
    quote do
      {unquote(d), unquote(m), unquote(s)}
    end
  end

  def cos(degrees) do
    degrees
    |> to_radians
    |> :math.cos()
  end

  def sin(degrees) do
    degrees
    |> to_radians
    |> :math.sin()
  end

  def asin(degrees) do
    degrees
    |> to_radians
    |> :math.asin()
  end

  def acos(degrees) do
    degrees
    |> to_radians
    |> :math.acos()
  end

  def tan(degrees) do
    degrees
    |> to_radians
    |> :math.tan()
  end

  def atan(0, 0) do
    :undefined
  end

  def atan(y, x) do
    cond do
      x == 0 && y != 0 -> signum(y) * deg(90.0)
      x >= 0 -> to_degrees(:math.atan(y / x))
      x < 0 -> to_degrees(:math.atan(y / x)) + signum(y) * deg(180.0)
    end
    |> mod(360.0)
  end

  def atan_r(0, 0) do
    :NaN
  end

  def atan_r(y, x) do
    cond do
      x == 0 && y != 0 -> signum(y) * :math.pi() / 2.0
      x >= 0 -> :math.atan(y / x)
      x < 0 -> :math.atan(y / x) + signum(y) * :math.pi()
    end
  end

  @doc """
  Returns the minimum number for which
  the given function returns a `truthy`
  value.

  """
  @spec min(number(), function()) :: number()
  def min(i, fun) when is_number(i) and is_function(fun) do
    if fun.(i), do: i, else: min(i + 1, fun)
  end

  @doc """
  Returns the maximum number for which
  the given function returns a `truthy`
  value.

  """
  @spec max(number(), function()) :: number()
  def max(i, fun) when is_number(i) and is_function(fun) do
    if fun.(i), do: max(i + 1, fun), else: i - 1
  end

  @spec poly(number(), [number()]) :: number()
  def poly(_, []), do: 0
  def poly(x, [a | a_s]), do: a + x * poly(x, a_s)

  def amod(x, y) when y != 0 do
    y + mod(x, -y)
  end

  @spec signum(number()) :: -1 | 0 | 1
  def signum(x) when x > 0, do: 1
  def signum(x) when x < 0, do: -1
  def signum(_), do: 0

  @spec sigma([[number(), ...]], function()) :: number()
  def sigma(list_of_lists, fun) do
    if Enum.all?(list_of_lists, &(&1 == [])) do
      0
    else
      # [hd(l) || l <- list_of_lists]
      current = Enum.map(list_of_lists, &hd/1)
      # [tl(l) || l <- list_of_lists]
      next = Enum.map(list_of_lists, &tl/1)
      fun.(current) + sigma(next, fun)
    end
    |> Kernel.*(1.0)
  end

  @doc """
  Calculates the modulo of a number (integer, float).

  Note that this function uses `floored division` whereas the builtin `rem`
  function uses `truncated division`.

  See [Wikipedia](https://en.wikipedia.org/wiki/Modulo_operation) for an
  explanation of the difference.

  ## Examples

      iex> Astro.Math,mod(1234.0, 5)
      4.0

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

  def final(k, pred) do
    new_k = k + 1

    if !pred.(new_k) do
      k
    else
      final(new_k, pred)
    end
  end

  def next(k, pred) do
    if pred.(k) do
      k
    else
      next(k + 1, pred)
    end
  end

  @spec invert_angular(function(), number(), number(), number()) :: number()
  def invert_angular(f, y, a, b) do
    # returns X such that A =< X =< B for which f(X) = Y
    # where |X-X0| < Tolerance
    tolerance = 1 / 100_000.0
    phi = fn l, u -> u - l < tolerance end
    psi = fn x -> mod(f.(x) - y, 360.0) < deg(180.0) end
    bisection_search(a, b, phi, psi)
  end

  @spec bisection_search(number(), number(), function(), function()) :: number()
  def bisection_search(u, v, phi, psi) do
    x = (v + u) / 2.0

    if phi.(u, v) do
      x
    else
      if psi.(x) do
        bisection_search(u, x, phi, psi)
      else
        bisection_search(x, v, phi, psi)
      end
    end
  end
end
