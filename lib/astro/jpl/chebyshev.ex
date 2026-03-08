defmodule Spk.Chebyshev do
  @moduledoc """
  Evaluates Chebyshev polynomials of the first kind using the Clenshaw
  recurrence relation.

  For a list of coefficients `[c0, c1, ..., cn]` and a normalised argument
  `s ∈ [-1, +1]`, computes:

      sum(c_k * T_k(s), k = 0..n)

  where `T_k` is the Chebyshev polynomial of degree `k`.

  The Clenshaw algorithm evaluates this sum in O(n) with no explicit
  computation of individual polynomials, and is numerically superior to
  the explicit Horner form for Chebyshev series.
  """

  @doc """
  Evaluates the Chebyshev sum for the given coefficient list and argument.

  `coeffs` — list of Chebyshev coefficients `[c0, c1, ..., cn]`.
  `s`      — normalised argument in `[-1, +1]`.
  """
  @spec evaluate([float()], float()) :: float()
  def evaluate([], _s), do: 0.0
  def evaluate([c0], _s), do: c0

  def evaluate(coeffs, s) do
    # Clenshaw backward recurrence:
    #   b_k = c_k + 2s·b_{k+1} - b_{k+2},  k = n-1 .. 1,  b_{n+1} = b_{n+2} = 0
    #   result = c_0 + s·b_1 - b_2
    #
    # Iteration order [c_n, c_{n-1}, ..., c_1]:
    #   drop c_0 (head), reverse the remaining tail.
    two_s = 2.0 * s
    [c0 | tail] = coeffs

    {b1, b2} =
      tail
      |> Enum.reverse()
      |> Enum.reduce({0.0, 0.0}, fn c, {b_next, b_after} ->
        {c + two_s * b_next - b_after, b_next}
      end)

    c0 + s * b1 - b2
  end
end
