// Dialog pattern adapted from ToolDeck image_files_channel.cpp; export-only.
#include "inventory_export_channel.h"
#include "inventory_export_file.h"
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <wrl/client.h>

namespace {
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
HRESULT ChooseDestination(HWND owner, std::wstring* path) {
  ComPtr<IFileSaveDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileSaveDialog, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) return hr;
  FILEOPENDIALOGOPTIONS options;
  hr = dialog->GetOptions(&options);
  if (FAILED(hr)) return hr;
  options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR |
      FOS_DONTADDTORECENT | FOS_NOTESTFILECREATE;
  options &= ~FOS_OVERWRITEPROMPT;
  hr = dialog->SetOptions(options);
  if (FAILED(hr)) return hr;
  const COMDLG_FILTERSPEC filter{L"Asset Desk inventory JSON", L"*.json"};
  hr = dialog->SetFileTypes(1, &filter);
  if (FAILED(hr)) return hr;
  hr = dialog->SetDefaultExtension(L"json");
  if (FAILED(hr)) return hr;
  hr = dialog->SetFileName(L"asset-desk-inventory.json");
  if (FAILED(hr)) return hr;
  hr = dialog->SetTitle(L"Save inventory JSON (new file, no overwrite)");
  if (FAILED(hr)) return hr;
  hr = dialog->Show(owner);
  if (FAILED(hr)) return hr;
  ComPtr<IShellItem> item;
  hr = dialog->GetResult(&item);
  if (FAILED(hr)) return hr;
  PWSTR selected = nullptr;
  hr = item->GetDisplayName(SIGDN_FILESYSPATH, &selected);
  if (SUCCEEDED(hr)) *path = selected;
  CoTaskMemFree(selected);
  return hr;
}
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateInventoryExportChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "asset_desk/inventory_export", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner](const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const bool hashing = call.method_name() == "sha256";
    if (!hashing && call.method_name() != "saveJson") {
      result->NotImplemented(); return;
    }
    const auto* bytes = call.arguments()
        ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
    if (!bytes || bytes->size() > 1024 * 1024 || (!hashing && bytes->size() < 2)) {
      result->Error("invalid_export", "Invalid inventory byte size."); return;
    }
    if (hashing) {
      const auto digest = InventorySha256(*bytes);
      if (digest.empty()) { result->Error("hash_failed", "Unable to verify checksum."); return; }
      result->Success(EncodableValue(digest)); return;
    }
    std::wstring path;
    const HRESULT hr = ChooseDestination(owner, &path);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Success(); return; }
    if (FAILED(hr)) { result->Error("dialog_failed", "Unable to open save dialog."); return; }
    const auto outcome = WriteNewInventoryJson(path, *bytes);
    if (outcome != InventorySaveResult::saved) {
      result->Error(outcome == InventorySaveResult::exists ? "file_exists" : "save_failed",
          "Unable to save. Choose a new local .json filename."); return;
    }
    // Do not expose or log the chosen private path.
    result->Success(EncodableValue(true));
  });
  return channel;
}
