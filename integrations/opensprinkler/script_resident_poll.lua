require("user.opensprinkler")

-- Resident script — calls sprinkler.Resident_Poll() on every timer tick.
-- Set the resident script sleep interval to 60 seconds in the C-Bus project.
sprinkler.Resident_Poll()
