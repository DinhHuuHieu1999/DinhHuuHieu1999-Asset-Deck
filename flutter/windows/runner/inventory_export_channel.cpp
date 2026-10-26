// Dialog pattern adapted from ToolDeck image_files_channel.cpp; explicit export and read-only inspection.
#include "inventory_export_channel.h"
#include "inventory_export_file.h"
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <wrl/client.h>

namespace {
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
HRESULT ChooseDestination(HWND owner, std::wstring* path, bool recovery) {
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
  hr = dialog->SetFileName(recovery ? L"asset-desk-import-recovery.json" : L"asset-desk-inventory.json");
  if (FAILED(hr)) return hr;
  hr = dialog->SetTitle(recovery ? L"Save private import recovery JSON (no overwrite)" : L"Save inventory JSON (new file, no overwrite)");
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
HRESULT ChooseInspectionSource(HWND owner, std::wstring* path, bool recovery) {
  ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) return hr;
  FILEOPENDIALOGOPTIONS options;
  hr = dialog->GetOptions(&options);
  if (FAILED(hr)) return hr;
  options |= FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST |
      FOS_NOCHANGEDIR | FOS_DONTADDTORECENT;
  options &= ~(FOS_ALLOWMULTISELECT | FOS_PICKFOLDERS);
  hr = dialog->SetOptions(options);
  if (FAILED(hr)) return hr;
  const COMDLG_FILTERSPEC filter{L"Asset Desk inventory JSON", L"*.json"};
  hr = dialog->SetFileTypes(1, &filter);
  if (FAILED(hr)) return hr;
  hr = dialog->SetTitle(recovery ? L"Choose private import recovery JSON (no automatic replay)" : L"Inspect local inventory JSON (no import)");
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
    const bool recovery = call.method_name() == "chooseRecoveryJson" ||
        call.method_name() == "sha256Recovery" || call.method_name() == "saveRecoveryJson";
    if (call.method_name() == "chooseInspectionJson" || call.method_name() == "chooseRecoveryJson") {
      if (call.arguments() && !std::holds_alternative<std::monostate>(*call.arguments())) {
        result->Error("invalid_inspection", "No input path or arguments accepted."); return;
      }
      std::wstring path;
      const HRESULT hr = ChooseInspectionSource(owner, &path, recovery);
      if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Success(); return; }
      if (FAILED(hr)) { result->Error("dialog_failed", "Unable to open file dialog."); return; }
      std::vector<uint8_t> bytes;
      if (!(recovery ? ReadRecoveryJson(path, &bytes) : ReadInventoryJson(path, &bytes))) {
        result->Error("read_failed", "Unable to read a bounded local JSON file."); return;
      }
      result->Success(EncodableValue(bytes)); return;
    }
    const bool hashing = call.method_name() == "sha256" || call.method_name() == "sha256Recovery";
    if (!hashing && call.method_name() != "saveJson" && call.method_name() != "saveRecoveryJson") {
      result->NotImplemented(); return;
    }
    const auto* bytes = call.arguments()
        ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
    const size_t limit = recovery ? 2 * 1024 * 1024 : 1024 * 1024;
    if (!bytes || bytes->size() > limit || (!hashing && bytes->size() < 2)) {
      result->Error("invalid_export", "Invalid inventory byte size."); return;
    }
    if (hashing) {
      const auto digest = recovery ? RecoverySha256(*bytes) : InventorySha256(*bytes);
      if (digest.empty()) { result->Error("hash_failed", "Unable to verify checksum."); return; }
      result->Success(EncodableValue(digest)); return;
    }
    std::wstring path;
    const HRESULT hr = ChooseDestination(owner, &path, recovery);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Success(); return; }
    if (FAILED(hr)) { result->Error("dialog_failed", "Unable to open save dialog."); return; }
    const auto outcome = recovery ? WriteNewRecoveryJson(path, *bytes) : WriteNewInventoryJson(path, *bytes);
    if (outcome != InventorySaveResult::saved) {
      result->Error(outcome == InventorySaveResult::exists ? "file_exists" : "save_failed",
          "Unable to save. Choose a new local .json filename."); return;
    }
    // Do not expose or log the chosen private path.
    result->Success(EncodableValue(true));
  });
  return channel;
}
