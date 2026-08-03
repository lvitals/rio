package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local files = require("rio.cli.files")

describe("Rio CLI Files", function()
    it("creates nested directories and lists files without shell commands", function()
        local root = (os.getenv("TMPDIR") or "/tmp") .. "/rio_cli_files_test_" .. tostring({}):match("0x(.+)$")
        files.remove_tree(root)

        assert.truthy(files.ensure_dir(files.join(root, "a", "b")))
        assert.is_true(files.is_dir(files.join(root, "a", "b")))

        assert.truthy(files.write(files.join(root, "a", "b", "one.lua"), "return 1"))
        assert.truthy(files.write(files.join(root, "a", "b", "two.txt"), "two"))

        local listed = files.list(files.join(root, "a", "b"), { mode = "file", pattern = "%.lua$" })
        assert.equals(1, #listed)
        assert.equals("one.lua", files.basename(listed[1]))

        local found = files.find(root, { pattern = "%.txt$" })
        assert.equals(1, #found)
        assert.equals("two.txt", files.basename(found[1]))

        assert.truthy(files.remove_matching(files.join(root, "a", "b"), "%.lua$"))
        assert.is_false(files.exists(files.join(root, "a", "b", "one.lua")))
        assert.is_true(files.exists(files.join(root, "a", "b", "two.txt")))

        assert.truthy(files.remove_tree(root))
        assert.is_false(files.exists(root))
    end)
end)
