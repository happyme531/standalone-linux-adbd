#include "adb.h"
#include "adb_auth.h"
#include "adb_unique_fd.h"
#include "daemon/jdwp_service.h"
#include "daemon/tradeinmode.h"

#include <adbd_fs.h>
#include <diagnose_usb.h>

bool auth_required = false;
bool socket_access_allowed = true;

void adbd_auth_init() {}
void adbd_cloexec_auth_socket() {}

void adbd_auth_verified(atransport* transport) {
    handle_online(transport);
    send_connect(transport);
}

bool adbd_auth_verify(const char*, size_t, const std::string&, std::string*) {
    return true;
}

void adbd_auth_confirm_key(atransport* transport) {
    adbd_auth_verified(transport);
}

void adbd_notify_framework_connected_key(atransport*) {}
void send_auth_request(atransport*) {}
int init_jdwp() {
    return 0;
}

asocket* create_jdwp_service_socket() {
    return nullptr;
}

asocket* create_jdwp_tracker_service_socket() {
    return nullptr;
}

asocket* create_app_tracker_service_socket() {
    return nullptr;
}

unique_fd create_jdwp_connection_fd(pid_t) {
    return {};
}

std::string UsbNoPermissionsShortHelpText() {
    return "USB transport unavailable in TCP-only adbd";
}

std::string UsbNoPermissionsLongHelpText() {
    return UsbNoPermissionsShortHelpText();
}

bool should_enter_tradeinmode() {
    return false;
}

void enter_tradeinmode(const char*) {}

bool is_in_tradeinmode() {
    return false;
}

bool is_in_tradein_evaluation_mode() {
    return false;
}

bool allow_tradeinmode_command(std::string_view) {
    return true;
}

extern "C" void adbd_fs_config(const char*, int, const char*, uid_t*, gid_t*, mode_t*, uint64_t*) {
    // Preserve the mode and ownership requested by the host on a normal Linux
    // filesystem. Android's fs_config policy does not apply here.
}
