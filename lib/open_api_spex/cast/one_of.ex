defmodule OpenApiSpex.Cast.OneOf do
  @moduledoc false
  alias OpenApiSpex.Cast
  alias OpenApiSpex.Cast.Error
  alias OpenApiSpex.Schema

  def cast(%_{schema: %{type: _, oneOf: []}} = ctx) do
    error(ctx, [], [])
  end

  def cast(%{schema: %{type: _, oneOf: schemas}} = ctx) do
    castable_schemas =
      Enum.reduce(schemas, {[], []}, fn schema, {results, error_schemas} ->
        schema = OpenApiSpex.resolve_schema(schema, ctx.schemas)

        with {:ok, value} <-
               Cast.cast(%{ctx | schema: %{schema | "x-struct": nil}}),
             :ok <- check_required_fields(ctx, value) do
          {[{:ok, value, schema} | results], error_schemas}
        else
          _error -> {results, [schema | error_schemas]}
        end
      end)

    case castable_schemas do
      {[{:ok, %_{} = value, _}], _} -> {:ok, value}
      {[{:ok, value, %Schema{"x-struct": nil}}], _} -> {:ok, value}
      {[{:ok, value, %Schema{"x-struct": module}}], _} -> {:ok, struct(module, value)}
      {success_results, failed_schemas} -> error(ctx, success_results, failed_schemas)
    end
  end

  ## Private functions

  defp error(ctx, success_results, failed_schemas) do
    valid_schemas = Enum.map(success_results, &elem(&1, 2))

    message =
      case {valid_schemas, failed_schemas} do
        {[], []} -> "no schemas given"
        {[], _} -> "no schemas validate"
        {_, _} -> "more than one schemas validate"
      end

    Cast.error(
      ctx,
      {:one_of,
       %{
         message: message,
         failed_schemas: Enum.map(failed_schemas, &error_message_item/1),
         valid_schemas: Enum.map(valid_schemas, &error_message_item/1)
       }}
    )
  end

  defp error_message_item({:ok, _value, schema}) do
    error_message_item(schema)
  end

  defp error_message_item(schema) do
    case schema do
      %{title: title, type: type} when not is_nil(title) ->
        "Schema(title: #{inspect(title)}, type: #{inspect(type)})"

      %{type: type} ->
        "Schema(type: #{inspect(type)})"
    end
  end

  defp check_required_fields(ctx, %{} = acc) do
    required = ctx.schema.required || []

    input_keys = Map.keys(acc)
    missing_keys = required -- input_keys

    if missing_keys == [] do
      :ok
    else
      errors =
        Enum.map(missing_keys, fn key ->
          ctx = %{ctx | path: [key | ctx.path]}
          Error.new(ctx, {:missing_field, key})
        end)

      {:error, ctx.errors ++ errors}
    end
  end

  defp check_required_fields(_ctx, _acc), do: :ok
end
