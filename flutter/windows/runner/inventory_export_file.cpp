// Adapted from ToolDeck catalog_digest.cpp and image_result_file.cpp.
#include "inventory_export_file.h"
#include <windows.h>
#include <bcrypt.h>
#include <algorithm>
#include <cwctype>

namespace {
bool ValidDestination(const std::wstring& path, const std::wstring& extension) {
  // Local drive paths only; exclude device/UNC namespaces and alternate streams.
  if (path.size() < 9 || path.size() > 32760 || !iswalpha(path[0]) ||
      path[1] != L':' || path[2] != L'\\' ||
      path.find(L':', 2) != std::wstring::npos ||
      path.find(L'\0') != std::wstring::npos) return false;
  const std::wstring drive = path.substr(0, 3);
  const auto drive_type = GetDriveTypeW(drive.c_str());
  if (drive_type != DRIVE_FIXED && drive_type != DRIVE_REMOVABLE) return false;
  std::wstring upper = path;
  std::transform(upper.begin(), upper.end(), upper.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
  if (upper.substr(upper.size() - extension.size()) != extension) return false;
  size_t start = 3;
  while (start < upper.size()) {
    const auto end = upper.find_first_of(L"\\/", start);
    const auto part = upper.substr(start, end - start);
    if (part.empty() || part == L"." || part == L".." ||
        part.back() == L'.' || part.back() == L' ') return false;
    auto stem = part.substr(0, part.find(L'.'));
    while (!stem.empty() && stem.back() == L' ') stem.pop_back();
    if (stem == L"CON" || stem == L"PRN" || stem == L"AUX" || stem == L"NUL" ||
        (stem.size() == 4 && (stem.substr(0, 3) == L"COM" || stem.substr(0, 3) == L"LPT") &&
         ((stem[3] >= L'1' && stem[3] <= L'9') || stem[3] == L'\u00b9' ||
          stem[3] == L'\u00b2' || stem[3] == L'\u00b3'))) return false;
    if (end == std::wstring::npos) break;
    const auto attributes = GetFileAttributesW(path.substr(0, end).c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
    start = end + 1;
  }
  return true;
}
InventorySaveResult WriteNewResult(const std::wstring& path,
                              const std::vector<uint8_t>& bytes) {
  // CREATE_NEW is the actual race-safe no-overwrite boundary, not an exists check.
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE | DELETE, 0, nullptr,
                                  CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    const auto error = GetLastError();
    return error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS
               ? InventorySaveResult::exists : InventorySaveResult::failed;
  }
  DWORD written = 0;
  const bool saved = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                               &written, nullptr) && written == bytes.size() &&
                     FlushFileBuffers(file);
  if (!saved) {
    // Delete only the newly created file through our exclusive handle on failure.
    FILE_DISPOSITION_INFO disposition{TRUE};
    SetFileInformationByHandle(file, FileDispositionInfo, &disposition, sizeof(disposition));
  }
  CloseHandle(file);
  return saved ? InventorySaveResult::saved : InventorySaveResult::failed;
}
}  // namespace


std::string InventorySha256(const std::vector<uint8_t>& bytes) {
  if (bytes.size() > 1024 * 1024) return {};
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
    return {};
  unsigned char digest[32]{};
  const auto status = BCryptHash(algorithm, nullptr, 0,
      const_cast<PUCHAR>(bytes.data()), static_cast<ULONG>(bytes.size()),
      digest, sizeof(digest));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status < 0) return {};
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  result.reserve(64);
  for (const auto byte : digest) {
    result.push_back(hex[byte >> 4]);
    result.push_back(hex[byte & 15]);
  }
  return result;
}

InventorySaveResult WriteNewInventoryJson(const std::wstring& path,
                                         const std::vector<uint8_t>& bytes) {
  if (!ValidDestination(path, L".JSON") || bytes.size() < 2 ||
      bytes.size() > 1024 * 1024 || bytes.front() != '{' || bytes.back() != '}' ||
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
          reinterpret_cast<const char*>(bytes.data()), static_cast<int>(bytes.size()),
          nullptr, 0) == 0) return InventorySaveResult::invalid;
  return WriteNewResult(path, bytes);
}

// Bounded inspection input, adapted from ToolDeck ReadCatalogJson.
bool ReadInventoryJson(const std::wstring& path, std::vector<uint8_t>* bytes) {
  if (!bytes) return false;
  bytes->clear();
  if (!ValidDestination(path, L".JSON")) return false;
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  BY_HANDLE_FILE_INFORMATION info{};
  LARGE_INTEGER size{};
  const bool valid = GetFileType(file) == FILE_TYPE_DISK &&
      GetFileInformationByHandle(file, &info) &&
      !(info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) &&
      GetFileSizeEx(file, &size) && size.QuadPart >= 2 && size.QuadPart <= 1024 * 1024;
  bool read = false;
  if (valid) {
    bytes->resize(static_cast<size_t>(size.QuadPart));
    DWORD count = 0;
    read = ReadFile(file, bytes->data(), static_cast<DWORD>(bytes->size()), &count, nullptr) &&
        count == bytes->size();
  }
  CloseHandle(file);
  if (!read) bytes->clear();
  return read;
}
