vim.opt.runtimepath:prepend(vim.fn.getcwd())

local gomono = require("go_mono_repo")
local go = require("go_mono_repo.go")
local handlers = require("go_mono_repo.handlers")
local rootmod = require("go_mono_repo.root")
local scope = require("go_mono_repo.scope")

local function assert_true(value, msg)
	if not value then
		error(msg, 2)
	end
end

local function rel_set(root, files)
	local set = {}
	local prefix = vim.fn.fnamemodify(root, ":p")
	for _, file in ipairs(files or {}) do
		set[vim.fn.fnamemodify(file, ":p"):gsub("^" .. vim.pesc(prefix), "")] = true
	end
	return set
end

local target = vim.fn.expand("~/coding/gns3util")
vim.cmd.chdir(target)
gomono.setup({
	keymaps = {},
	persist = false,
	notify = false,
})

local root, err = rootmod.find(target)
assert_true(root == target, err or ("expected root " .. target .. ", got " .. tostring(root)))

local entries = go.discover_entrypoints(root)
local labels = {}
for _, entry in ipairs(entries) do
	labels[entry.label] = true
end
assert_true(labels["gns3util"], "missing gns3util entrypoint")
assert_true(labels["master"], "missing master entrypoint")
assert_true(labels["file-store"], "missing file-store entrypoint")
assert_true(vim.tbl_count(labels) == 3, "expected exactly 3 entrypoints, got " .. vim.inspect(vim.tbl_keys(labels)))

local master, master_err = scope.compute(root, "./cmd/master", { force = true })
assert_true(master, master_err or "master scope failed")
local master_files = rel_set(root, master.files)
assert_true(master_files["cmd/master/main.go"], "master scope missing cmd/master/main.go")
assert_true(master_files["internal/master/handlers/job_handlers.go"], "master scope missing job_handlers.go")
assert_true(not master_files["cmd/file-store/main.go"], "master scope leaked cmd/file-store/main.go")
assert_true(
	not master_files["internal/file-store/handlers/filestore_handlers.go"],
	"master scope leaked filestore_handlers.go"
)
local master_routes = handlers.collect(root)
local has_master_route = false
local has_filestore_route = false
for _, item in ipairs(master_routes) do
	has_master_route = has_master_route or item.text:match("GET%s+/api/v1/jobs%s+.*ListJobs") ~= nil
	has_filestore_route = has_filestore_route or item.text:match("ListBucketFiles") ~= nil
end
assert_true(has_master_route, "master handlers missing ListJobs route")
assert_true(not has_filestore_route, "master handlers leaked file-store route")

local filestore, fs_err = scope.compute(root, "./cmd/file-store", { force = true })
assert_true(filestore, fs_err or "file-store scope failed")
local filestore_files = rel_set(root, filestore.files)
assert_true(filestore_files["cmd/file-store/main.go"], "file-store scope missing cmd/file-store/main.go")
assert_true(
	filestore_files["internal/file-store/handlers/filestore_handlers.go"],
	"file-store scope missing filestore_handlers.go"
)
assert_true(not filestore_files["cmd/master/main.go"], "file-store scope leaked cmd/master/main.go")
assert_true(
	not filestore_files["internal/master/handlers/master_handlers.go"],
	"file-store scope leaked master_handlers.go"
)
local filestore_routes = handlers.collect(root)
local has_bucket_route = false
local has_job_route = false
for _, item in ipairs(filestore_routes) do
	has_bucket_route = has_bucket_route or item.text:match("GET%s+/api/v1/buckets%s+.*ListBuckets") ~= nil
	has_job_route = has_job_route or item.text:match("ListJobs") ~= nil
end
assert_true(has_bucket_route, "file-store handlers missing ListBuckets route")
assert_true(not has_job_route, "file-store handlers leaked master ListJobs route")

print("go_mono_repo smoke OK")
