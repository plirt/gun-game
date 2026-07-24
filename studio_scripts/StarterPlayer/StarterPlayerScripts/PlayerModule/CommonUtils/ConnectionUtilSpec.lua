local CorePackages = game:GetService("CorePackages")

local JestGlobals = require(CorePackages.Packages.Dev.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local AppCommonLib = require(CorePackages.Workspace.Packages.AppCommonLib)
local Signal = AppCommonLib.Signal

local ConnectionUtil = require(script.Parent.ConnectionUtil)

describe("ConnectionUtil", function()
	it("should instantiate", function()
		local connectionUtil = ConnectionUtil.new()

		expect(connectionUtil).never.toBeNil()
	end)

	it("should track a connection", function()
		local connectionUtil = ConnectionUtil.new()
		local signal = Signal.new()
		local result = ""

		connectionUtil:trackConnection(
			"Signal",
			signal:Connect(function(p)
				result = p
			end)
		)
		signal:fire("Testing")

		expect(result).toBe("Testing")
	end)

	it("should disconnect from signal", function()
		local connectionUtil = ConnectionUtil.new()
		local signal = Signal.new()
		local result = ""

		connectionUtil:trackConnection(
			"Signal",
			signal:Connect(function(p)
				result = p
			end)
		)
		connectionUtil:disconnect("Signal")
		signal:fire("Testing")

		expect(result).toBe("")
	end)

	it("should disconnect from all", function()
		local connectionUtil = ConnectionUtil.new()
		local primarySignal = Signal.new()
		local secondarySignal = Signal.new()
		local tertiarySignal = Signal.new()

		local primaryResult = ""
		local secondaryResult = ""
		local tertiaryResult = ""

		connectionUtil:trackConnection(
			"Signal",
			primarySignal:Connect(function(p)
				primaryResult = p
			end)
		)
		connectionUtil:trackConnection(
			"Signal1",
			secondarySignal:Connect(function(p)
				secondaryResult = p
			end)
		)
		connectionUtil:trackConnection(
			"Signal2",
			tertiarySignal:Connect(function(p)
				tertiaryResult = p
			end)
		)
		connectionUtil:disconnectAll()
		primarySignal:fire("TestingPrimary")
		primarySignal:fire("TestingSecondary")
		primarySignal:fire("TestingTertiary")


		expect(primaryResult).toBe("")
		expect(secondaryResult).toBe("")
		expect(tertiaryResult).toBe("")
	end)

	it("should call manual disconnect", function()
		local connectionUtil = ConnectionUtil.new()
		local result = ""

		connectionUtil:trackBoundFunction("Manual", function()
			result = "Disconnected"
		end)
		connectionUtil:disconnect("Manual")

		expect(result).toBe("Disconnected")
	end)
end)

