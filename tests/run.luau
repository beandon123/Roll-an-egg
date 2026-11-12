--!nocheck
-- Runs every test. From the repository root:
--     lune run tests/run

local process = require("@lune/process")

local harness = require("./harness")

local specs = {
	"./specs/config.spec",
	"./specs/shared.spec",
	"./specs/eggModels.spec",
	"./specs/runwaySim.spec",
	"./specs/server.smoke.spec",
	"./specs/client.smoke.spec",
}

for _, spec in specs do
	require(spec)(harness)
end

process.exit(harness.finish())
