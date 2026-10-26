// Opt-in synthetic helper test; never opens a dialog or contacts a backend.
#include "inventory_export_file.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  const std::filesystem::path directory(argv[1]);
  if (!std::filesystem::is_directory(directory) ||
      !std::filesystem::is_empty(directory)) return 3;
  int count = 0;
  auto check = [&count](bool ok) {
    ++count;
    if (!ok) std::cerr << "Failed assertion " << count << "\n";
    return ok;
  };
  const std::vector<uint8_t> empty;
  const std::vector<uint8_t> abc{'a','b','c'};
  const std::vector<uint8_t> unicode{0xc3,0xa9,0xe4,0xb8,0xad,0xf0,0x9f,0x9a,0x80};
  if (!check(InventorySha256(empty) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) return 1;
  if (!check(InventorySha256(abc) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")) return 1;
  if (!check(InventorySha256(unicode) == "d137a1bc13dddbffdab0fd5ceab553100966e171a325cf9fe26fe9c553e5e578")) return 1;
  if (!check(InventorySha256(std::vector<uint8_t>(1024*1024+1)).empty())) return 1;
  const auto target = directory / L"synthetic.json";
  const std::vector<uint8_t> json{'{','}'};
  if (!check(WriteNewInventoryJson(target.wstring(), json) == InventorySaveResult::saved)) return 1;
  if (!check(WriteNewInventoryJson(target.wstring(), std::vector<uint8_t>{'{',' ','}'}) == InventorySaveResult::exists)) return 1;
  std::ifstream input(target, std::ios::binary);
  const std::string contents((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  if (!check(contents == "{}")) return 1;
  for (const auto& name : {L"invalid.txt", L"CON.json", L"NUL.json", L"bad.json:stream"}) {
    if (!check(WriteNewInventoryJson((directory / name).wstring(), json) == InventorySaveResult::invalid)) return 1;
  }
  if (!check(WriteNewInventoryJson(L"relative.json", json) == InventorySaveResult::invalid)) return 1;
  if (!check(WriteNewInventoryJson((directory/L"bad-utf8.json").wstring(), std::vector<uint8_t>{'{',0xff,'}'}) == InventorySaveResult::invalid)) return 1;
  if (!check(WriteNewInventoryJson((directory/L"empty.json").wstring(), empty) == InventorySaveResult::invalid)) return 1;
  if (!check(WriteNewInventoryJson((directory/L"oversize.json").wstring(), std::vector<uint8_t>(1024*1024+1)) == InventorySaveResult::invalid)) return 1;
  if (!check(std::distance(std::filesystem::directory_iterator(directory), std::filesystem::directory_iterator{}) == 1)) return 1;
  // Inspection contract: existing synthetic files only; never erase fixture data.
  input.close();
  std::vector<uint8_t> inspected{9};
  if (!check(ReadInventoryJson(target.wstring(), &inspected) && inspected == json)) return 1;
  if (!check(!ReadInventoryJson(target.wstring(), nullptr))) return 1;
  for (const auto& path : {directory / L"missing.json", directory / L"invalid.txt",
                          directory / L"CON.json", directory / L"bad.json:stream"}) {
    inspected = {9};
    if (!check(!ReadInventoryJson(path.wstring(), &inspected) && inspected.empty())) return 1;
  }
  if (!check(!ReadInventoryJson(L"relative.json", &inspected))) return 1;
  auto create = [&directory](const wchar_t* name, size_t length) {
    const auto file = directory / name;
    std::ofstream output(file, std::ios::binary);
    const std::string content(length, ' ');
    output.write(content.data(), static_cast<std::streamsize>(content.size()));
    output.close();
    return output.good();
  };
  if (!check(create(L"zero.json", 0) && create(L"one.json", 1) &&
             create(L"limit.json", 1024 * 1024) && create(L"large.json", 1024 * 1024 + 1))) return 1;
  for (const auto* name : {L"zero.json", L"one.json", L"large.json"}) {
    inspected = {9};
    if (!check(!ReadInventoryJson((directory / name).wstring(), &inspected) && inspected.empty())) return 1;
  }
  if (!check(ReadInventoryJson((directory / L"limit.json").wstring(), &inspected) &&
             inspected.size() == 1024 * 1024)) return 1;
  // Native byte selection is not JSON validation; Dart rejects these spaces.
  if (!check(std::filesystem::file_size(target) == 2 &&
             std::filesystem::file_size(directory / L"large.json") == 1024 * 1024 + 1)) return 1;
  // Recovery has an independent 2 MiB boundary; no inventory limit is widened.
  if (!check(RecoverySha256(abc) == InventorySha256(abc))) return 1;
  if (!check(RecoverySha256(std::vector<uint8_t>(1024*1024+1)).size() == 64)) return 1;
  if (!check(RecoverySha256(std::vector<uint8_t>(2*1024*1024+1)).empty())) return 1;
  std::vector<uint8_t> recovery(1024*1024+1, ' ');
  recovery.front() = '{'; recovery.back() = '}';
  const auto recovery_target = directory / L"recovery.json";
  if (!check(WriteNewInventoryJson(recovery_target.wstring(), recovery) == InventorySaveResult::invalid)) return 1;
  if (!check(WriteNewRecoveryJson(recovery_target.wstring(), recovery) == InventorySaveResult::saved)) return 1;
  if (!check(WriteNewRecoveryJson(recovery_target.wstring(), json) == InventorySaveResult::exists)) return 1;
  if (!check(ReadRecoveryJson(recovery_target.wstring(), &inspected) && inspected == recovery)) return 1;
  if (!check(!ReadInventoryJson(recovery_target.wstring(), &inspected) && inspected.empty())) return 1;
  if (!check(create(L"recovery-limit.json", 2*1024*1024) && create(L"recovery-large.json", 2*1024*1024+1))) return 1;
  if (!check(ReadRecoveryJson((directory/L"recovery-limit.json").wstring(), &inspected) && inspected.size() == 2*1024*1024)) return 1;
  if (!check(!ReadRecoveryJson((directory/L"recovery-large.json").wstring(), &inspected) && inspected.empty())) return 1;
  if (!check(WriteNewRecoveryJson((directory/L"bad-recovery.txt").wstring(), json) == InventorySaveResult::invalid)) return 1;
  std::cout << count << " native assertions passed; synthetic output retained\n";
  return 0;
}
