require("user.sonos")

-- Resident script — calls sonos.Resident_Poll() on every timer tick.
-- Set the resident script sleep interval to 30 seconds in the C-Bus project.
sonos.Resident_Poll()
