if not describe then
    print("Usage: busted test/fixtures/failing_spec.lua")
    os.exit(1)
end

describe("Rio CLI failing fixture", function()
    it("fails intentionally", function()
        assert.equals("expected", "actual")
    end)
end)
