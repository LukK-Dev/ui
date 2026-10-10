package ui

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 1000

measure_text :: proc(text: string, font_size: f32) -> [2]f32 {
	return rl.MeasureTextEx(
		rl.GetFontDefault(),
		strings.clone_to_cstring(text, context.temp_allocator),
		font_size,
		0,
	)
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "UI Testbed")

	ui := Ui {
		viewport_width = WINDOW_WIDTH,
		viewport_height = WINDOW_HEIGHT,
		interface = {measure_text_proc = measure_text},
	}
	defer {
		for _, node in ui.id_to_node {
			free(node)
		}
		delete(ui.id_to_node)
	}

	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		if rl.IsWindowResized() do on_window_resize(&ui, cast(u32)rl.GetScreenWidth(), cast(u32)rl.GetScreenHeight())

		begin_layout(&ui)

		// fill_test(&ui)
		editor(&ui)

		draw_commands := end_layout(&ui)

		rl.BeginDrawing()
		{
			for command in draw_commands {
				switch c in command {
				case Draw_Rect:
					rl.DrawRectangleV(
						c.rect.position,
						{c.rect.width, c.rect.height},
						cast(rl.Color)(255 * c.color),
					)
				case Draw_Text:
					rl.DrawTextEx(
						rl.GetFontDefault(),
						strings.clone_to_cstring(c.text, context.temp_allocator),
						c.position,
						c.font_size,
						0,
						cast(rl.Color)(255 * c.color),
					)
				}
			}
		}
		rl.EndDrawing()

		delete(draw_commands)
	}

	rl.CloseWindow()
}

fill_test :: proc(ui: ^Ui) {
	begin_node(
		ui,
		sizing = {
			width = pixels(f32(rl.GetScreenWidth())),
			height = pixels(f32(rl.GetScreenHeight())),
		},
		padding = padding_all(20),
		child_gap = 20,
		background_color = {0.2, 0.2, 0.3, 1.0},
	)
	{
		begin_node(
			ui,
			sizing = {width = pixels(200), height = FILL},
			background_color = {0.9, 0.4, 0.6, 1.0},
		)
		end_node(ui)

		begin_node(
			ui,
			sizing = {width = {type = .Fill, min = 20}, height = FILL},
			background_color = {0.4, 0.9, 0.6, 1.0},
		)
		end_node(ui)

		begin_node(
			ui,
			sizing = {width = pixels(200), height = FILL},
			background_color = {0.6, 0.4, 0.9, 1.0},
		)
		end_node(ui)
	}
	end_node(ui)
}

editor :: proc(ui: ^Ui) {
	begin_node(
		ui,
		sizing = FILL_ALL,
		direction = .Top_To_Bottom,
		background_color = {0.15, 0.15, 0.15, 1.0},
	)
	{
		top_bar(ui)

		begin_node(
			ui,
			flags = {.Draw_Text},
			sizing = FIT_TEXT,
			text = "Hello, World!",
			font_size = 200,
		)
		end_node(ui)
	}
	end_node(ui)
}

top_bar :: proc(ui: ^Ui) {
	begin_node(
		ui,
		sizing = {width = FILL, height = FIT},
		child_gap = 10,
		padding = padding_all(10),
		background_color = {0.2, 0.2, 0.2, 1.0},
	)
	{
		begin_node(ui, sizing = sizing_pixels(100, 75), background_color = {0.25, 0.25, 0.25, 1.0})

		end_node(ui)
		begin_node(ui, sizing = sizing_pixels(200, 75), background_color = {0.25, 0.25, 0.25, 1.0})
		end_node(ui)

		begin_node(ui, sizing = sizing_pixels(75, 75), background_color = {0.25, 0.25, 0.25, 1.0})
		end_node(ui)

		begin_node(
			ui,
			sizing = {width = FILL, height = pixels(75)},
			background_color = {0.2, 0.2, 0.2, 1.0},
		)
		end_node(ui)

		begin_node(ui, sizing = sizing_pixels(100, 75), background_color = {0.25, 0.25, 0.25, 1.0})
		end_node(ui)
	}
	end_node(ui)
}
