require("user.opensprinkler")

-- Event script — manually run or stop an irrigation zone from the dashboard.
--
-- Attach to a C-Bus User Parameter write event (e.g. "Irrigation_RunZone").
-- Write the zone number (1-based) to run that zone for the default duration.
-- Write 0 to stop all zones.
--
-- Example: write 2 to run Zone 2 for DEFAULT_RUN_SECONDS.
--          write 0 to stop all zones.

local DEFAULT_RUN_SECONDS = 300   -- 5 minutes — adjust as needed

local val = tonumber(event.getvalue())

if val == nil then
  return
elseif val == 0 then
  sprinkler.StopAll()
elseif val > 0 then
  sprinkler.RunZone(val, DEFAULT_RUN_SECONDS)
end
