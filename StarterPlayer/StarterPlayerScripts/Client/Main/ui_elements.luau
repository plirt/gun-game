local vide = require(script.Parent.vide)
local create = vide.create

local ui_elements = {}

function ui_elements.h(class_name, props, children)
	props = props or {}
	for _, child in children or {} do
		table.insert(props, child)
	end
	return create(class_name)(props)
end

function ui_elements.mount(parent, node)
	return vide.mount(function()
		return node
	end, parent)
end

function ui_elements.label(text, size, color, bold)
	return ui_elements.h("TextLabel", {
		BackgroundTransparency = 1,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		Text = text,
		TextColor3 = color or Color3.fromRGB(245, 245, 245),
		TextSize = size or 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, (size or 14) + 10),
	})
end

function ui_elements.button(text, on_click, width, muted, name, extra_props)
	local props = {
		Name = name or "Button",
		AutoButtonColor = not muted,
		BackgroundColor3 = muted and Color3.fromRGB(34, 34, 34) or Color3.fromRGB(245, 245, 245),
		BorderColor3 = Color3.fromRGB(245, 245, 245),
		BorderSizePixel = 1,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = muted and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(0, 0, 0),
		TextSize = 12,
		Size = UDim2.new(0, width or 108, 0, 30),
		Activated = on_click,
	}
	for key, value in extra_props or {} do
		props[key] = value
	end
	return ui_elements.h("TextButton", props)
end

function ui_elements.micro_label(text, color)
	return ui_elements.label(string.upper(text), 10, color or Color3.fromRGB(155, 155, 155), true)
end

function ui_elements.stat_bar(name, value, accent, order)
	value = math.clamp(value or 0, 0, 1)
	return ui_elements.h("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order or 1 }, {
		ui_elements.h("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = string.upper(name), TextColor3 = Color3.fromRGB(185, 185, 185), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, 82, 1, 0) }),
		ui_elements.h("Frame", { BackgroundColor3 = Color3.fromRGB(32, 32, 32), BorderSizePixel = 0, Position = UDim2.new(0, 88, 0.5, -3), Size = UDim2.new(1, -88, 0, 6) }, {
			ui_elements.h("Frame", { BackgroundColor3 = accent or Color3.fromRGB(245, 245, 245), BorderSizePixel = 0, Size = UDim2.new(value, 0, 1, 0) }),
		}),
	})
end

function ui_elements.panel(props, children)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(0, 0, 0)
	props.BackgroundTransparency = props.BackgroundTransparency or 0.02
	props.BorderColor3 = props.BorderColor3 or Color3.fromRGB(245, 245, 245)
	props.BorderSizePixel = props.BorderSizePixel or 1
	return ui_elements.h("Frame", props, children)
end

return ui_elements
