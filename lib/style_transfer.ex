defmodule Membrane.StyleTransfer do
  @moduledoc """
  `Membrane.Filter` transferring style of the video frames using AI model.

  It receives and returns raw video frames in RGB format.

  Available styles are:
   - `:candy`
   - `:kaganawa`
   - `:mosaic`
   - `:mosaic_mobile`
   - `:picasso`
   - `:princess`
   - `:udnie`
   - `:vangogh`

  Style can be selected by specyfing `:style` option during spawning a child or by sending `{:set_style, style}` notification from a parent.

  To optimize the element, you can pass some positive integer to `:batch_size` option, but remember that it will icrease the latency.
  """
  use Membrane.Filter

  defguard is_pos_integer(term) when is_integer(term) and term > 0

  def_input_pad :input,
    accepted_format:
      %Membrane.RawVideo{pixel_format: :RGB, height: height, width: width}
      when is_pos_integer(height) and is_pos_integer(width)

  def_output_pad :output,
    accepted_format:
      %Membrane.RawVideo{pixel_format: :RGB, height: height, width: width}
      when is_pos_integer(height) and is_pos_integer(width)

  def_options style: [
                required?: true,
                spec: style(),
                description: """
                Initial style used by the element.

                Can be changed by sending `{:set_style, style}` notification from a parent.
                """
              ],
              batch_size: [
                require?: false,
                default: 1,
                spec: non_neg_integer(),
                description: """
                Number of video frames passed in one batch to the model.

                Can be increased in order to optimize the element at the cost of increased latency.

                Default to 1.
                """
              ]

  @styles [:candy, :kaganawa, :mosaic, :mosaic_mobile, :picasso, :princess, :udnie, :vangogh]

  @type style ::
          unquote(
            @styles
            |> Bunch.Typespec.enum_to_alternative()
          )

  @spec styles() :: [style()]
  def styles(), do: @styles

  @impl true
  def handle_init(_ctx, %{style: style} = opts) when style in @styles do
    state = %{
      current_style: style,
      batch_size: opts.batch_size,
      models: %{},
      batch: []
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    models =
      @styles
      |> Map.new(fn style ->
        model = get_model_path(style) |> Ortex.load()
        {style, model}
      end)

    {[], %{state | models: models}}
  end

  defp get_model_path(style) do
    Application.get_application(__MODULE__)
    |> :code.priv_dir()
    |> Path.join("#{style}.onnx")
  end

  @impl true
  def handle_parent_notification({:set_style, style}, _ctx, state) when style in @styles do
    {[], %{state | current_style: style}}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    state = Map.update!(state, :batch, &(&1 ++ [buffer]))

    if length(state.batch) >= state.batch_size do
      flush_batch(ctx.pads.input.stream_format, state)
    else
      {[], state}
    end
  end

  defp flush_batch(format, state) do
    {batch, state} = Map.get_and_update!(state, :batch, &{&1, []})

    input_tensor =
      batch
      |> Enum.map(&preprocess(&1.payload, format))
      |> Nx.stack()

    out_tensor = predict(input_tensor, state)

    out_buffers =
      out_tensor
      |> Nx.backend_transfer(EXLA.Backend)
      |> Nx.to_batched(1)
      |> Enum.map(&postprocess(&1, format))
      |> Enum.zip(batch)
      |> Enum.map(fn {payload, buffer} -> %{buffer | payload: payload} end)

    {[buffer: {:output, out_buffers}], state}
  end

  defp predict(tensor, state) do
    offsets = Nx.tensor([1.0, 1.0, 1.0, 1.0], type: :f32)
    {output} = Ortex.run(state.models[state.current_style], {tensor, offsets})
    output
  end

  defp preprocess(payload, format) do
    payload
    |> Nx.from_binary(:u8, backend: EXLA.Backend)
    |> Nx.as_type(:f32)
    |> Nx.reshape({format.height, format.width, 3})
    |> Nx.transpose(axes: [2, 0, 1])
  end

  defp postprocess(tensor, format) do
    tensor
    |> Nx.backend_transfer(EXLA.Backend)
    |> Nx.reshape({3, format.height, format.width})
    |> Nx.transpose(axes: [1, 2, 0])
    |> clamp()
    |> Nx.round()
    |> Nx.as_type(:u8)
    |> Nx.reverse(axes: [1])
    |> Nx.to_binary()
  end

  defp clamp(tensor) do
    tensor
    |> Nx.max(0.0)
    |> Nx.min(255.0)
  end
end
