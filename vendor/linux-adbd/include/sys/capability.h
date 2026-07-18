#pragma once

// Linux TCP-only adbd does not enter Android's minijail privilege-dropping
// path, but upstream includes this header unconditionally for daemon builds.
