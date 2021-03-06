defmodule EEx.Tokenizer do
  @moduledoc false

  @doc """
  Tokenizes the given char list or binary.

  It returns {:ok, list} with the following tokens:

    * `{:text, contents}`
    * `{:expr, line, marker, contents}`
    * `{:start_expr, line, marker, contents}`
    * `{:middle_expr, line, marker, contents}`
    * `{:end_expr, line, marker, contents}`

  Or `{:error, line, error}` in case of errors.
  """
  def tokenize(bin, line) when is_binary(bin) do
    tokenize(String.to_char_list(bin), line)
  end

  def tokenize(list, line) do
    tokenize(list, line, [], [])
  end

  defp tokenize('<%%' ++ t, line, buffer, acc) do
    tokenize t, line, [?%, ?<|buffer], acc
  end

  defp tokenize('<%#' ++ t, line, buffer, acc) do
    case expr(t, line, []) do
      {:error, _, _} = error -> error
      {:ok, _, new_line, rest} ->
        tokenize rest, new_line, buffer, acc
    end
  end

  defp tokenize('<%' ++ t, line, buffer, acc) do
    {marker, t} = retrieve_marker(t)

    case expr(t, line, []) do
      {:error, _, _} = error -> error
      {:ok, expr, new_line, rest} ->
        token = token_name(expr)
        acc   = tokenize_text(buffer, acc)
        final = {token, line, marker, Enum.reverse(expr)}
        tokenize rest, new_line, [], [final | acc]
    end
  end

  defp tokenize('\n' ++ t, line, buffer, acc) do
    tokenize t, line + 1, [?\n|buffer], acc
  end

  defp tokenize([h|t], line, buffer, acc) do
    tokenize t, line, [h|buffer], acc
  end

  defp tokenize([], _line, buffer, acc) do
    {:ok, Enum.reverse(tokenize_text(buffer, acc))}
  end

  # Retrieve marker for <%

  defp retrieve_marker('=' ++ t) do
    {'=', t}
  end

  defp retrieve_marker(t) do
    {'', t}
  end

  # Tokenize an expression until we find %>

  defp expr([?%, ?>|t], line, buffer) do
    {:ok, buffer, line, t}
  end

  defp expr('\n' ++ t, line, buffer) do
    expr t, line + 1, [?\n|buffer]
  end

  defp expr([h|t], line, buffer) do
    expr t, line, [h|buffer]
  end

  defp expr([], line, _buffer) do
    {:error, line, "missing token '%>'"}
  end

  # Receive an expression content and check
  # if it is a start, middle or an end token.
  #
  # Start tokens finish with `do` and `fn ->`
  # Middle tokens are marked with `->` or keywords
  # End tokens contain only the end word

  defp token_name([h|t]) when h in [?\s, ?\t] do
    token_name(t)
  end

  defp token_name('od' ++ [h|_]) when h in [?\s, ?\t, ?)] do
    :start_expr
  end

  defp token_name('>-' ++ rest) do
    rest = Enum.reverse(rest)

    # Tokenize the remaining passing check_terminators as
    # false, which relax the tokenizer to not error on
    # unmatched pairs. Then, we check if there is a "fn"
    # token and, if so, it is not followed by an "end"
    # token. If this is the case, we are on a start expr.
    case :elixir_tokenizer.tokenize(rest, 1, file: "eex", check_terminators: false) do
      {:ok, _line, _column, tokens} ->
        tokens   = Enum.reverse(tokens)
        fn_index = fn_index(tokens)

        if fn_index && end_index(tokens) > fn_index do
          :start_expr
        else
          :middle_expr
        end
      _error ->
        :middle_expr
    end
  end

  defp token_name('esle' ++ t),   do: check_spaces(t, :middle_expr)
  defp token_name('retfa' ++ t),  do: check_spaces(t, :middle_expr)
  defp token_name('hctac' ++ t),  do: check_spaces(t, :middle_expr)
  defp token_name('eucser' ++ t), do: check_spaces(t, :middle_expr)
  defp token_name('dne' ++ t),    do: check_spaces(t, :end_expr)

  defp token_name(_) do
    :expr
  end

  defp fn_index(tokens) do
    Enum.find_index tokens, fn
      {:fn_paren, _} -> true
      {:fn, _}       -> true
      _                -> false
    end
  end

  defp end_index(tokens) do
    Enum.find_index(tokens, &match?({:end, _}, &1)) || :infinity
  end

  defp check_spaces(string, token) do
    if Enum.all?(string, &(&1 in [?\s, ?\t])) do
      token
    else
      :expr
    end
  end

  # Tokenize the buffered text by appending
  # it to the given accumulator.

  defp tokenize_text([], acc) do
    acc
  end

  defp tokenize_text(buffer, acc) do
    [{:text, Enum.reverse(buffer)} | acc]
  end
end
