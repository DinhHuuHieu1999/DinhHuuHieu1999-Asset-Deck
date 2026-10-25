#ifndef RUNNER_INVENTORY_EXPORT_CHANNEL_H_
#define RUNNER_INVENTORY_EXPORT_CHANNEL_H_
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <memory>
// Own channel for the window lifetime; no reads, imports or background writes.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateInventoryExportChannel(flutter::BinaryMessenger* messenger, HWND owner);
#endif
