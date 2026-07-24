local CorePackages = game:GetService("CorePackages")

local JestGlobals = require(CorePackages.Packages.Dev.JestGlobals)
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local waitForEvents = require(CorePackages.Workspace.Packages.TestUtils).DeferredLuaHelpers.waitForEvents

local CameraWrapper = require(script.Parent.CameraWrapper)

describe("CameraWrapper", function()
    it("should instantiate", function()
		local cameraWrapper = CameraWrapper.new()

		expect(cameraWrapper).never.toBeNil()
	end)

    it("should return updated camera", function()
        local cameraWrapper = CameraWrapper.new()
        cameraWrapper:Enable()

        local camera = Instance.new("Camera")
        camera.Parent = game.Workspace

        expect(cameraWrapper:getCamera()).toBe(game.Workspace.CurrentCamera)
        expect(cameraWrapper:getCamera()).never.toBe(camera)
        game.Workspace.CurrentCamera = camera

        waitForEvents()
        expect(cameraWrapper:getCamera()).toBe(game.Workspace.CurrentCamera)
        expect(cameraWrapper:getCamera()).toBe(camera)
    end)
end)
