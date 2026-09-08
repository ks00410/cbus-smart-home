require("user.ecowitt")

-- Resident script — calls ecowitt.Resident_Poll() on every timer tick.
-- Set the resident script sleep interval to 60 seconds in the C-Bus project.
ecowitt.Resident_Poll()
