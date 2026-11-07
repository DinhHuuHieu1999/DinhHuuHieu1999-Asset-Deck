#ifndef RUNNER_INVENTORY_EXPORT_FILE_H_
#define RUNNER_INVENTORY_EXPORT_FILE_H_
#include <cstdint>
#include <string>
#include <vector>
enum class InventorySaveResult { saved, exists, invalid, failed };
// CSV-only 1 MiB UTF-8 writer; retains CREATE_NEW and local-path restrictions.
InventorySaveResult WriteNewInventoryCsv(const std::wstring& path,
                                        const std::vector<uint8_t>& bytes);
// Bounded Windows CNG SHA-256; empty string indicates failure.
std::string InventorySha256(const std::vector<uint8_t>& bytes);
// Create a new local .json only, never overwrite; cleanup only our own failed write.
InventorySaveResult WriteNewInventoryJson(const std::wstring& path,
                                         const std::vector<uint8_t>& bytes);
// Read only one explicitly selected local .json; never follow final reparse points.
bool ReadInventoryJson(const std::wstring& path, std::vector<uint8_t>* bytes);
// Recovery-only 2 MiB envelope helpers; existing inventory wrappers stay at 1 MiB.
std::string RecoverySha256(const std::vector<uint8_t>& bytes);
InventorySaveResult WriteNewRecoveryJson(const std::wstring& path,
                                        const std::vector<uint8_t>& bytes);
bool ReadRecoveryJson(const std::wstring& path, std::vector<uint8_t>* bytes);
#endif
