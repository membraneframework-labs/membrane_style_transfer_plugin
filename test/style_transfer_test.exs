defmodule Membrane.StyleTransfer.Test do
  use ExUnit.Case, async: true

  alias Membrane.Testing
  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  defmodule ImageSource do
    alias Membrane.RawVideo
    use Membrane.Source

    @image_path "./test/fixtures/orginal_bunny.jpg"

    def_output_pad :output, accepted_format: %RawVideo{pixel_format: :RGB}, flow_control: :push

    @impl true
    def handle_init(_ctx, _opts), do: {[], %{}}

    @impl true
    def handle_playing(_ctx, state) do
      image = Image.open!(@image_path)

      stream_format =
        %RawVideo{
          pixel_format: :RGB,
          height: Image.height(image),
          width: Image.width(image),
          framerate: nil,
          aligned: nil
        }

      payload =
        Image.to_nx!(image)
        |> Nx.as_type(:u8)
        |> Nx.to_binary()

      buffer = %Membrane.Buffer{payload: payload}

      actions = [
        stream_format: {:output, stream_format},
        buffer: {:output, buffer}
      ]

      {actions, state}
    end
  end

  defp do_test(style) do
    spec =
      child(ImageSource)
      |> child(%Membrane.StyleTransfer{style: style})
      |> child(:sink, Testing.Sink)

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    assert_sink_stream_format(pipeline, :sink, stream_format)
    assert_sink_buffer(pipeline, :sink, buffer)

    image =
      buffer.payload
      |> Nx.from_binary(:u8)
      |> Nx.reshape({stream_format.height, stream_format.width, 3},
        names: [:height, :width, :bands]
      )
      |> Image.from_nx!()

    fixture_image = Image.open!("./test/fixtures/#{style}_bunny.png")

    {:ok, difference_ratio, _image} = Image.compare(image, fixture_image)

    assert difference_ratio < 0.1

    Testing.Pipeline.terminate(pipeline)
  end

  [:candy, :kaganawa, :mosaic, :mosaic_mobile, :picasso, :princess, :udnie, :vangogh]
  |> Enum.map(fn style ->
    test "#{inspect(style)} style" do
      unquote(style)
      |> do_test()
    end
  end)
end
