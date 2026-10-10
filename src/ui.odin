package ui

import "base:runtime"
import "core:fmt"
import "core:hash"

// possible improvements: - if a node using fit sizing has at least one child that can grow, we size the node to take up as much space of its parent as possible
//                        - overflow handling:
//                          - wrapping of child nodes, when overflowing the parent node
//                          - clip overflow
//                        - handle multiple fill nodes in the same parent
//                        - alignment
//                        - implement Percent sizing type

FILL :: Sizing_Axis {
	type = .Fill,
}

FILL_ALL :: Sizing {
	width = {type = .Fill},
	height = {type = .Fill},
}

FIT :: Sizing_Axis {
	type = .Fit,
}

FIT_ALL :: Sizing {
	width = {type = .Fit},
	height = {type = .Fit},
}

FIT_TEXT :: Sizing {
	width = {type = .Fit_Text},
	height = {type = .Fit_Text},
}

Rect :: struct {
	width, height: f32,
	position:      [2]f32,
}

Layout_Direction :: enum {
	Left_To_Right = 0,
	Top_To_Bottom,
}

Sizing_Type :: enum {
	Pixels,
	Percent,
	Fill,
	Fit,
	Fit_Text,
}

Sizing_Axis :: struct {
	type:  Sizing_Type,
	value: f32,
	min:   f32,
}

Sizing :: struct {
	width:  Sizing_Axis,
	height: Sizing_Axis,
}

Padding :: struct {
	left, top, right, bottom: f32,
}

Style :: struct {
	sizing:           Sizing,
	padding:          Padding,
	child_gap:        f32,
	direction:        Layout_Direction,
	background_color: [4]f32,
	font_size:        f32,
	text_color:       [4]f32,
}

Draw_Rect :: struct {
	rect:  Rect,
	color: [4]f32,
}

Draw_Text :: struct {
	position:  [2]f32,
	text:      string,
	font_size: f32,
	color:     [4]f32,
}

Draw_Command :: union {
	Draw_Rect,
	Draw_Text,
}

Ui_Interface :: struct {
	measure_text_proc: proc(text: string, font_size: f32) -> [2]f32,
}

Id :: distinct u32

Flag :: enum {
	Draw_Background,
	Draw_Text,
}

Node :: struct {
	id:            Id,
	flags:         bit_set[Flag],
	generation:    u64,
	style:         Style,
	text:          string,
	computed_rect: Rect,
	parent:        ^Node,
	next_sibling:  ^Node,
	first_child:   ^Node,
	child_count:   u32,
}

Ui :: struct {
	interface:       Ui_Interface,
	viewport_width:  u32,
	viewport_height: u32,
	root:            ^Node,
	current_parent:  ^Node,
	generation:      u64,
	id_to_node:      map[Id]^Node,
}

prune_tree :: proc(ui: ^Ui) {
	for id, node in ui.id_to_node {
		if (ui.generation - node.generation) > 1 {
			child := node.first_child
			for child != nil {
				child.parent = node.parent
				child = child.next_sibling
			}

			free(node)
			delete_key(&ui.id_to_node, id)
		}
	}
}

on_window_resize :: proc(ui: ^Ui, new_width, new_height: u32) {
	ui.viewport_width = new_width
	ui.viewport_height = new_height
}

begin_layout :: proc(ui: ^Ui) {
	if ui.root == nil {
		id: Id = #hash("root", "fnv32a")
		root := new(Node)
		root.id = id
		ui.id_to_node[id] = root
		ui.root = root
	}

	ui.root.style.sizing = sizing_pixels(f32(ui.viewport_width), f32(ui.viewport_height))

	ui.generation += 1
	prune_tree(ui)

	// NOTE: we want to rebuild the hierarchy every frame, so we need to clear it at the start of each layout
	for _, node in ui.id_to_node {
		node.parent = nil
		node.next_sibling = nil
		node.first_child = nil
		node.child_count = 0
	}

	ui.root.generation = ui.generation
	ui.current_parent = ui.root
}

end_layout :: proc(ui: ^Ui) -> [dynamic]Draw_Command {
	compute_node_sizes(ui)
	compute_node_positions(ui)
	return build_draw_commands(ui.root)
}

begin_node :: proc(
	ui: ^Ui,
	id: Id = 0,
	flags: bit_set[Flag] = {.Draw_Background},
	sizing: Sizing,
	padding: Padding = {},
	child_gap: f32 = 0,
	direction: Layout_Direction = {},
	background_color: [4]f32 = {1, 1, 1, 1},
	text: string = "",
	font_size: f32 = 16,
	text_color: [4]f32 = {1, 1, 1, 1},
	loc := #caller_location,
) {
	id := id
	if id == 0 do id = id_from_caller_loc(loc)

	style := Style {
		sizing           = sizing,
		padding          = padding,
		child_gap        = child_gap,
		direction        = direction,
		background_color = background_color,
		font_size        = font_size,
		text_color       = text_color,
	}

	if !(id in ui.id_to_node) {
		node := new(Node)
		node^ = {
			id = id,
		}
		ui.id_to_node[id] = node
	}

	node := ui.id_to_node[id]
	node^.flags = flags
	node^.style = style
	node^.text = text
	node^.generation = ui.generation
	node^.parent = ui.current_parent

	if ui.current_parent.first_child == nil do ui.current_parent.first_child = node
	else {
		child := ui.current_parent.first_child
		for child.next_sibling != nil do child = child.next_sibling
		child.next_sibling = node
	}

	ui.current_parent.child_count += 1
	ui.current_parent = node
}

end_node :: proc(ui: ^Ui) {
	ui.current_parent = ui.current_parent.parent
}


build_draw_commands :: proc(root: ^Node) -> [dynamic]Draw_Command {
	commands: [dynamic]Draw_Command

	node_stack: [dynamic]^Node
	defer delete(node_stack)
	append(&node_stack, root)

	for len(node_stack) > 0 {
		node := pop(&node_stack)

		if .Draw_Background in node.flags {
			append(
				&commands,
				Draw_Rect{rect = node.computed_rect, color = node.style.background_color},
			)
		}

		if .Draw_Text in node.flags {
			append(
				&commands,
				Draw_Text {
					node.computed_rect.position,
					node.text,
					node.style.font_size,
					node.style.text_color,
				},
			)
		}

		child := node.first_child
		for child != nil {
			append(&node_stack, child)
			child = child.next_sibling
		}
	}

	return commands
}

compute_node_sizes :: proc(ui: ^Ui) {
	Stack_Element :: struct {
		node:    ^Node,
		visited: bool,
	}

	node_stack: [dynamic]Stack_Element
	defer delete(node_stack)
	append(&node_stack, Stack_Element{node = ui.root})

	for len(node_stack) > 0 {
		top := &node_stack[len(node_stack) - 1]
		node := top.node

		if top.visited {
			if node.style.sizing.width.type == .Fit {
				if node.child_count == 0 {
					node.computed_rect.width = node.style.sizing.width.min
				} else {
					width := node.style.padding.left + node.style.padding.right

					if node.style.direction == .Left_To_Right {
						width += node.style.child_gap * f32(node.child_count - 1)

						child := node.first_child
						for child != nil {
							width += child.computed_rect.width
							child = child.next_sibling
						}
					} else {
						greatest_width: f32 = 0
						child := node.first_child
						for child != nil {
							if child.computed_rect.width > greatest_width {
								greatest_width = child.computed_rect.width
							}
							child = child.next_sibling
						}
						width += greatest_width
					}

					node.computed_rect.width = width
				}
			}

			if node.style.sizing.height.type == .Fit {
				if node.child_count == 0 {
					node.computed_rect.height = node.style.sizing.height.min
				} else {
					height := node.style.padding.top + node.style.padding.bottom

					if node.style.direction == .Left_To_Right {
						greatest_height: f32 = 0
						current_child := node.first_child
						for current_child != nil {
							if current_child.computed_rect.height > greatest_height {
								greatest_height = current_child.computed_rect.height
							}

							current_child = current_child.next_sibling
						}
						height += greatest_height
					} else {
						height += node.style.child_gap * f32(node.child_count - 1)

						current_child := node.first_child
						for current_child != nil {
							height += current_child.computed_rect.height

							current_child = current_child.next_sibling
						}
					}

					node.computed_rect.height = height
				}
			}

			pop(&node_stack)
		} else {
			if node.style.sizing.width.type == .Pixels {
				node.computed_rect.width = node.style.sizing.width.value
			}

			if node.style.sizing.height.type == .Pixels {
				node.computed_rect.height = node.style.sizing.height.value
			}

			if node.text != "" {
				text_extends := ui.interface.measure_text_proc(node.text, node.style.font_size)

				if node.style.sizing.width.type == .Fit_Text {
					node.computed_rect.width = text_extends.x
				}

				if node.style.sizing.height.type == .Fit_Text {
					node.computed_rect.height = text_extends.y
				}
			}

			if node.style.sizing.width.type == .Fill {
				remaining_width := node.parent.computed_rect.width
				// fmt.printfln("%v", remaining_width)
				remaining_width -= node.parent.style.padding.left + node.parent.style.padding.right

				if node.parent.style.direction == .Left_To_Right {
					remaining_width -=
						f32(node.parent.child_count - 1) * node.parent.style.child_gap

					sibling := node.parent.first_child
					for sibling != nil {
						if sibling == node {
							sibling = sibling.next_sibling
							continue
						}

						remaining_width -= sibling.computed_rect.width

						sibling = sibling.next_sibling
					}
				}

				node.computed_rect.width = max(remaining_width, node.style.sizing.width.min)
			}

			if node.style.sizing.height.type == .Fill {
				remaining_height := node.parent.computed_rect.height
				remaining_height -=
					node.parent.style.padding.top + node.parent.style.padding.bottom

				if node.parent.style.direction == .Top_To_Bottom {
					remaining_height -=
						f32(node.parent.child_count - 1) * node.parent.style.child_gap

					sibling := node.parent.first_child
					for sibling != nil {
						if sibling == node {
							sibling = sibling.next_sibling
							continue
						}

						remaining_height -= sibling.computed_rect.height

						sibling = sibling.next_sibling
					}
				}

				node.computed_rect.height = max(remaining_height, node.style.sizing.height.min)
			}

			top.visited = true

			next_node := node.first_child
			for next_node != nil {
				append(&node_stack, Stack_Element{node = next_node})
				next_node = next_node.next_sibling
			}
		}
	}
}

compute_node_positions :: proc(ui: ^Ui) {
	node_stack: [dynamic]^Node
	defer delete(node_stack)

	append(&node_stack, ui.root)

	for len(node_stack) > 0 {
		current_parent := pop(&node_stack)

		position := current_parent.computed_rect.position
		position.x += current_parent.style.padding.left
		position.y += current_parent.style.padding.top

		previous_sibling_offset: f32 = 0

		current_child := current_parent.first_child
		for current_child != nil {
			child_gap_offset: f32 = 0
			if current_child != current_parent.first_child do child_gap_offset = current_parent.style.child_gap

			if current_parent.style.direction == .Left_To_Right {
				position.x += child_gap_offset + previous_sibling_offset

				previous_sibling_offset = current_child.computed_rect.width
			} else {
				position.y += child_gap_offset + previous_sibling_offset

				previous_sibling_offset = current_child.computed_rect.height
			}

			current_child.computed_rect.position = position

			append(&node_stack, current_child)

			current_child = current_child.next_sibling
		}
	}
}

id_from_caller_loc :: proc(loc: runtime.Source_Code_Location) -> Id {
	path_hash := hash.fnv32a(transmute([]u8)loc.file_path)
	procedure_hash := hash.fnv32a(transmute([]u8)loc.procedure, path_hash)
	return cast(Id)hash.fmix32(procedure_hash + cast(u32)loc.line)
}

sizing_pixels :: proc(width, height: f32) -> Sizing {
	return Sizing {
		width = Sizing_Axis{type = .Pixels, value = width, min = width},
		height = Sizing_Axis{type = .Pixels, value = height, min = height},
	}
}

pixels :: proc(value: f32) -> Sizing_Axis {
	return Sizing_Axis{type = .Pixels, value = value}
}

padding_all :: proc(value: f32) -> Padding {
	return Padding{left = value, top = value, right = value, bottom = value}
}
