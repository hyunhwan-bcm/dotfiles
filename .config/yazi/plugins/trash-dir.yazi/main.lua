--- trash-dir: `d` moves files into a trash FOLDER on the same filesystem.
--
-- Why not yazi's built-in trash?
--   * On macOS it goes through NSFileManager into ~/.Trash, which a terminal
--     app is not allowed to touch unless it has Full Disk Access
--     ("Operation not permitted").
--   * On sftp:// filesystems yazi has no trash at all ("Trash not supported").
--
-- This plugin renames each file into <home>/.yazi-trash on whatever
-- filesystem the file lives on: $HOME locally, the remote user's home over
-- sftp. Rename stays on one filesystem so it is instant even for huge files.
-- Restore by moving the file back; `g T` jumps to the local folder.
-- Nothing is ever auto-emptied.

local TRASH_NAME = ".yazi-trash"

-- Runs on the main thread: read the selection (or the hovered file).
local collect = ya.sync(function()
	local urls = {}
	local sel = cx.active.selected
	if #sel > 0 then
		for _, f in pairs(sel) do
			-- Selected yields File objects in current yazi; older versions yield Urls.
			local ok, u = pcall(function() return f.url end)
			urls[#urls + 1] = (ok and u) or f
		end
	else
		local h = cx.active.current.hovered
		if h then urls[1] = h.url end
	end
	return urls
end)

local function trash_root(url)
	local spec = url.spec
	if spec and spec.scheme == "sftp" then
		-- Single slash after the domain = relative to the remote home.
		return Url("sftp://" .. spec.domain .. "/" .. TRASH_NAME)
	end
	return Url(os.getenv("HOME") .. "/" .. TRASH_NAME)
end

local function unique_dest(root, name)
	local dest = root:join(name)
	if not fs.cha(dest) then
		return dest
	end
	return root:join(name .. "." .. os.date("%Y%m%d-%H%M%S"))
end

return {
	entry = function()
		local urls = collect()
		if #urls == 0 then
			return
		end

		local what = #urls == 1 and ("'" .. tostring(urls[1].name) .. "'") or (#urls .. " files")
		local ok = ya.confirm {
			pos = { "center", w = 60, h = 8 },
			title = "Trash",
			body = "Move " .. what .. " to " .. TRASH_NAME .. "?",
		}
		if not ok then
			return
		end

		local moved, failed = 0, {}
		for _, u in ipairs(urls) do
			local root = trash_root(u)
			local created, cerr = fs.create("dir_all", root)
			if not created and not fs.cha(root) then
				failed[#failed + 1] = tostring(u.name) .. ": " .. tostring(cerr)
			else
				local done, err = fs.rename(u, unique_dest(root, tostring(u.name)))
				if done then
					moved = moved + 1
				else
					failed[#failed + 1] = tostring(u.name) .. ": " .. tostring(err)
				end
			end
		end

		ya.emit("escape", {})
		if #failed > 0 then
			ya.notify {
				title = "Trash",
				content = moved .. " moved, " .. #failed .. " failed:\n" .. table.concat(failed, "\n"),
				level = "error",
				timeout = 8,
			}
		else
			ya.notify { title = "Trash", content = moved .. " moved to " .. TRASH_NAME, timeout = 3 }
		end
	end,
}
