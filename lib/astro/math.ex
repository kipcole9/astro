defmodule Astro.Math do
  @moduledoc false

  import Kernel, except: [min: 2, max: 2, ceil: 1, floor: 1]
  alias Astro.Time

  @radians_to_degrees 180.0 / :math.pi()

  def to_degrees(radians) do
    radians * @radians_to_degrees
  end

  def to_radians(degrees) do
    degrees / @radians_to_degrees
  end

  @compile {:inline, mt: 1}
  def mt(x), do: x

  @compile {:inline, deg: 1}
  def deg(x), do: x
  def angle(d, m, s), do: d + (m + s / Time.seconds_per_minute()) / Time.minutes_per_hour()
  def degrees_minutes_seconds(d, m, s), do: {d, m, s}

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
      x < 0 -> to_degrees(:math.atan(y / x)) + deg(180.0)
    end
    |> mod(360.0)
  end

  def floor(x) when x >= 0 do
    trunc(x)
  end

  def floor(x) when x < 0 do
    t = trunc(x)
    if x - t == 0 do
      t
    else
      t - 1
    end
  end

  def ceil(x) do
    -floor(-x)
  end

  # `min(I, Pred)' returns the first `I' value for which
  # `Pred(I)' returns `true', and searches by increments of `+1'.
  # @spec min(i :: number(), pred :: fn((i) -> boolean())) :: number() when i :: number()
  def min(i, p) when is_number(i) and is_function(p) do
    if p.(i) do
      i
    else
      min(i + 1, p)
    end
  end

  # @doc `max(I, Pred)' returns the last `I' value for which
  # `Pred(I)' returns `true', and searches by increments of `+1'.
  # As soon as `Pred(I)' returns `false', `I-1' is returned.
  # @spec max(i, pred :: fn((i) -> boolean())) :: number() when i :: number()
  def max(i, p) when is_number(i) and is_function(p) do
    if p.(i) do
      max(i + 1, P);
    else
      i - 1
    end
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

  # @spec sigma([[number(), ...]], () -> number()
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

  def degrees(degrees) do
    mod(degrees, 360)
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

  # @spec invert_angular(number() -> angle(), number(), number(), number()) :: number()
  def invert_angular(f, y, a, b) do
    # returns X such that A =< X =< B for which f(X) = Y
    # where |X-X0| < Tolerance
    tolerance = 1 / 100_000.0
    phi = fn l, u -> u - l < tolerance end
    psi = fn x -> mod(f.(x) - y, 360.0) < deg(180.0) end
    bisection_search(a, b, phi, psi)
  end

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
