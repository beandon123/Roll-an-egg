--!nocheck
-- Runs every test. From the repository root:
--     lune run tests/run

local process = require("@lune/process")

local harness = require("./harness")

local specs = {
	"./specs/config.spec",
	"./specs/shared.spec",
	"./specs/runwaySim.spec",
}

for _, spec in specs do
	require(spec)(harness)
end

process.exit(harness.finish())
