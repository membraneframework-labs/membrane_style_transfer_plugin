# Membrane Style Transfer Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_style_transfer_plugin.svg)](https://hex.pm/packages/membrane_style_transfer_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_style_transfer_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_style_transfer_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_style_transfer_plugin)

This repository contains `Membrane.StyleTransfer` - `Membrane` filter performing style transfer on raw video frames.

It uses [Ortex](https://github.com/elixir-nx/ortex) to run models serialized in `.onnx` format and [Nx](https://github.com/elixir-nx/nx) to perform data pre- and postprocessing. 

It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_style_transfer_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_style_transfer_plugin, github: "membraneframework-labs/membrane_style_transfer_plugin", tag: "v0.1.0"}
  ]
end
```

## Usage

Here we have 2 simple examples of usage `Membrane.StyleTransfer`. Both of them take video from the camera device available in your computer, perform style transfer and present the output video in the player.

In the beginning, install necessary dependencies.

```elixir
Mix.install([
  {:membrane_style_transfer_plugin, github: "membraneframework-labs/membrane_style_transfer_plugin", tag: "v0.1.0"},
  {:membrane_camera_capture_plugin, "~> 0.7.2"},
  {:membrane_ffmpeg_swscale_plugin, "~> 0.15.1"},
  {:membrane_sdl_plugin, "~> 0.18.2"}
])
```

Add implementation of the `Example` pipeline.

```elixir
defmodule Example do
  use Membrane.Pipeline

  alias Membrane.FFmpeg.SWScale

  @impl true
  def handle_init(_ctx, opts) do
    height = opts[:output_height]
    width = opts[:output_width]

    spec =
      child(Membrane.CameraCapture)
      |> child(%SWScale.PixelFormatConverter{format: :I420})
      |> child(%SWScale.Scaler{output_height: height, output_width: width})
      |> child(%SWScale.PixelFormatConverter{format: :RGB})
      |> child(%Membrane.StyleTransfer{style: opts[:style]})
      |> child(%SWScale.PixelFormatConverter{format: :I420})
      |> child(Membrane.SDL.Player)

    {[spec: spec], %{}}
  end
end
```

And run following script:

```elixir
{:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(Example, [style: :vangogh, output_height: 400, output_width: 400])
```

If you see that the latency of the output video is increasing, reduce `output_height` or/and `output_width`.
If you see no increase in the latency, you can also increase the value passed in both options.

You can also change the style of played video by changing value passed in `:style` option. Available styles are: `:candy`, `:kaganawa`, `:mosaic`, `:mosaic_mobile`, `:picasso`, `:princess`, `:udnie` and `:vangogh`.

In the previous example, we applied just one style. However, in the following example, different styles are applied in rotation after fixed time intervals.

```elixir 
defmodule RotatingExample do
  use Membrane.Pipeline

  alias Membrane.FFmpeg.SWScale
  alias Membrane.StyleTransfer

  @style_change_time_interval Membrane.Time.milliseconds(1_500)

  @impl true
  def handle_init(_ctx, opts) do
    height = opts[:output_height]
    width = opts[:output_width]
    first_style = :picasso

    spec =
      child(Membrane.CameraCapture)
      |> child(%SWScale.PixelFormatConverter{format: :I420})
      |> child(%SWScale.Scaler{output_height: height, output_width: width})
      |> child(%SWScale.PixelFormatConverter{format: :RGB})
      |> child(:style_tranfer, %StyleTransfer{style: first_style})
      |> child(%SWScale.PixelFormatConverter{format: :I420})
      |> child(Membrane.SDL.Player)

    {[spec: spec], %{current_style: first_style}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:timer, @style_change_time_interval}], state}
  end

  @impl true
  def handle_tick(:timer, _ctx, state) do
    new_style = 
      StyleTransfer.available_styles() 
      |> List.delete(state.current_style)
      |> Enum.random()

    notification = {:set_style, new_style}
    state = %{state | current_style: new_style}

    {[notify_child: {:style_tranfer, notification}], state}
  end
end

{:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(RotatingExample, [output_height: 400, output_width: 400])
```

## Copyright and License

Copyright 2024, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_style_transfer_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_style_transfer_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
