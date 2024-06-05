defmodule Membrane.StyleTransfer do
  alias Membrane.Native.RawVideo
  use Membrane.Filter

  def_input_pad :input, accepted_format: %RawVideo{pixel_format: :RGB}
  def_output_pad :output, accepted_format: %RawVideo{pixel_format: :RGB}

  def_options style: [required?: true, spec: atom()]

  @styles [:candy, :kaganawa, :mosaic, :mosaic_mobile, :picasso, :princess, :udnie, :vangogh]

  @impl true
  def handle_init(_ctx, %{style: style}) when style in @styles do
    state = %{models: %{}, current_style: style}
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
    format = ctx.pads.input.stream_format

    out_payload =
      buffer.payload
      |> preprocess(format)
      |> predict(state)
      |> postprocess(format)

    buffer = %{buffer | payload: out_payload}
    {[buffer: {:output, buffer}], state}
  end

  defp predict(tensor, state) do
    offsets = Nx.tensor([1.0, 1.0, 1.0, 1.0], type: :f32)
    {output} = Ortex.run(state.models[state.current_style], {tensor, offsets})
    output
  end

  defp preprocess(payload, format) do
    payload
    |> Nx.from_binary(:s8, backend: EXLA.Backend)
    |> Nx.as_type(:f32)
    |> Nx.reshape({format.height, format.width, 3})
    |> Nx.transpose(axes: [2, 0, 1])
    |> Nx.reshape({1, 3, format.height, format.width})
  end

  defp postprocess(tensor, format) do
    tensor
    |> Nx.backend_transfer(EXLA.Backend)
    |> Nx.reshape({3, format.height, format.width})
    |> Nx.transpose(axes: [1, 2, 0])
    |> clamp()
    |> Nx.round()
    |> Nx.as_type(:s8)
    |> Nx.reverse(axes: [1])
    |> Nx.to_binary()
  end

  defp clamp(tensor) do
    tensor
    |> Nx.max(0)
    |> Nx.min(255)
  end
end
