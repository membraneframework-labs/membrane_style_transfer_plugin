defmodule Membrane.StyleTransfer.Test do
  use ExUnit.Case, async: true

  alias Membrane.Testing
  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  @orginal_bunny_path "./test/fixtures/orginal_bunny.jpg"

  defp do_test(style) do
    image = Image.open!(@orginal_bunny_path)

    stream_format =
      %Membrane.RawVideo{
        pixel_format: :RGB,
        height: Image.height(image),
        width: Image.width(image),
        framerate: nil,
        aligned: true
      }

    payload =
      Image.to_nx!(image)
      |> Nx.as_type(:u8)
      |> Nx.to_binary()

    buffer = %Membrane.Buffer{payload: payload}

    spec =
      child(%Testing.Source{stream_format: stream_format, output: [buffer]})
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
      unquote(Macro.escape(style))
      |> do_test()
    end
  end)
end
