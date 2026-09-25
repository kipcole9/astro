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
    :math.fmod(degrees, 360.0)
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
    |> to_radians()
    |> :math.cos()
  end

  def sin(degrees) do
    degrees
    |> to_radians()
    |> :math.sin()
  end

  # The inverse functions take a ratio, not an angle, and return the angle in
  # degrees: Calendrical Calculations' `arcsin-degrees` and `arccos-degrees`.
  # Converting the ratio from degrees, as these once did, returned roughly the
  # ratio itself.
  def asin(ratio) do
    ratio
    |> :math.asin()
    |> to_degrees()
  end

  def acos(ratio) do
    ratio
    |> :math.acos()
    |> to_degrees()
  end

  def tan(degrees) do
    degrees
    |> to_radians()
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

  # Sums `fun.(term)` over coefficient terms already zipped into tuples at
  # compile time by `zip_terms/1`, so each call is one pass with no per-term
  # allocation. The fold runs right to left -- `f(t1) + (f(t2) + ... + 0.0)`
  # -- because that is the order the terms have always been summed in, and
  # floating-point addition is not associative: summing left to right would
  # change results in the last bit.
  @spec sigma([tuple()], (tuple() -> number())) :: float()
  def sigma(terms, fun) do
    List.foldr(terms, 0.0, fn term, sum -> fun.(term) + sum end)
  end

  # Zips parallel coefficient tables into the term tuples `sigma/2` consumes.
  # Meant for module attributes, so it runs at compile time. Tables of unequal
  # length raise rather than truncate: `Enum.zip/1` would silently drop the
  # surplus terms and hide a transcription error in the table. This checks
  # static library data at build time and never sees user input.
  @spec zip_terms([[number()]]) :: [tuple()]
  def zip_terms(tables) do
    case tables |> Enum.map(&length/1) |> Enum.uniq() do
      [_length] ->
        Enum.zip(tables)

      lengths ->
        raise ArgumentError, "coefficient tables differ in length: #{inspect(lengths)}"
    end
  end

  @doc """
  Evaluates Chebyshev polynomials of the first kind using the Clenshaw
  recurrence relation.

  For a list of coefficients `[c0, c1, ..., cn]` and a normalised argument
  `s ∈ [-1, +1]`, computes:

      sum(c_k * T_k(s), k = 0..n)

  where `T_k` is the Chebyshev polynomial of degree `k`.

  The Clenshaw algorithm evaluates this sum in O(n) with no explicit
  computation of individual polynomials, and is numerically superior to
  the explicit Horner form for Chebyshev series.

  `coeffs` — list of Chebyshev coefficients `[c0, c1, ..., cn]`.
  `s`      — normalised argument in `[-1, +1]`.
  """
  @spec evaluate_chebyshev([float()], float()) :: float()
  def evaluate_chebyshev(coeffs, s), do: evaluate_chebyshev_reversed(:lists.reverse(coeffs), s)

  @doc false
  # The same evaluation with the coefficients highest order first,
  # `[c_n, ..., c_1, c_0]` -- the order the Clenshaw recurrence consumes them
  # in. A caller that can produce them in that order, as the ephemeris reader
  # does straight from the file, avoids reversing a list.
  @spec evaluate_chebyshev_reversed([float()], float()) :: float()
  def evaluate_chebyshev_reversed([], _s), do: 0.0
  def evaluate_chebyshev_reversed([c0], _s), do: c0

  def evaluate_chebyshev_reversed(reversed, s) do
    # Clenshaw backward recurrence:
    #   b_k = c_k + 2s·b_{k+1} - b_{k+2},  k = n-1 .. 1,  b_{n+1} = b_{n+2} = 0
    #   result = c_0 + s·b_1 - b_2
    clenshaw(reversed, 2.0 * s, s, 0.0, 0.0)
  end

  # One Clenshaw step per coefficient from c_n down to c_1; c_0, last in the
  # list, closes the sum. Direct recursion rather than a reduce, so no closure
  # is called and no accumulator tuple is allocated per step. The arithmetic,
  # and its order, is unchanged.
  defp clenshaw([c0], _two_s, s, b1, b2), do: c0 + s * b1 - b2

  defp clenshaw([c | rest], two_s, s, b_next, b_after),
    do: clenshaw(rest, two_s, s, c + two_s * b_next - b_after, b_next)

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
