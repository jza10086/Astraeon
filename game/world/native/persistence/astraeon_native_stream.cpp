#include "astraeon_native_stream.h"
#include "astraeon_content_registry.h"
#include "storage/voxel_buffer.h"
#include "util/godot/core/class_db.h"
#include <godot_cpp/classes/project_settings.hpp>
#include <array>
#include <cstdio>
#include <filesystem>
#include <cstring>
#include <chrono>
#ifdef _WIN32
#include <io.h>
#include <share.h>
#else
#include <unistd.h>
#endif
namespace zylann::voxel {
namespace {
constexpr size_t HEADER = 128, RECORD = 8208;
using Record = std::array<unsigned char, RECORD>;
uint32_t crc(const unsigned char *data, size_t size) {
    uint32_t c = 0xffffffffu;
    for (size_t i = 0; i < size; ++i) {
        c ^= data[i];
        for (int bit = 0; bit < 8; ++bit) c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u)));
    }
    return ~c;
}
void put32(unsigned char *p, uint32_t v) { for (int i = 0; i < 4; ++i) p[i] = static_cast<unsigned char>(v >> (8 * i)); }
uint32_t get32(const unsigned char *p) { return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24); }
FILE *open_file(const std::filesystem::path &path, bool create) {
#ifdef _WIN32
    FILE *file = _wfsopen(path.c_str(), create ? L"w+b" : L"r+b", _SH_DENYNO);
    return file;
#else
    return fopen(path.c_str(), create ? "w+b" : "r+b");
#endif
}
bool sync_file(FILE *file) {
    if (fflush(file) != 0) return false;
#ifdef _WIN32
    return _commit(_fileno(file)) == 0;
#else
    return fsync(fileno(file)) == 0;
#endif
}
int floor4(int v) { return v >= 0 ? v / 4 : (v + 1) / 4 - 1; }
bool valid(const Record &r) { return get32(r.data()) != 0 && get32(r.data() + 4) == 4096 && get32(r.data() + RECORD - 4) == crc(r.data(), RECORD - 4); }
bool empty(const Record &r) { for (auto v : r) if (v) return false; return true; }
}
bool AstraeonNativeStream::open_world(String directory, int seed, int biome_layout, PackedStringArray state_keys, String world_id) {
    std::lock_guard<std::mutex> guard(_mutex);
    if (!_directory.empty()) { fail("A stream cannot be reopened; create a new stream."); return false; }
    if (biome_layout < 0 || biome_layout > 1 || state_keys.size() < 2 || state_keys.size() > 65536 || state_keys[0] != "astraeon:air/default") { fail("Invalid content table or layout."); return false; }
    if(!AstraeonContentRegistry::validate_table(directory,state_keys,world_id)){fail("Content registry identity or state ordering mismatch");return false;}
    String encoded;
    for (int i = 0; i < state_keys.size(); ++i) {
        if (state_keys[i].is_empty() || state_keys[i].contains("\n")) { fail("Invalid state key."); return false; }
        for (int j = 0; j < i; ++j) if (state_keys[i] == state_keys[j]) { fail("Duplicate state key."); return false; }
        encoded += state_keys[i] + "\n";
    }
    if(world_id.length()!=32){fail("Missing world registry identity");return false;} _world_id=world_id; _state_count = state_keys.size();
    const String absolute = ::godot::ProjectSettings::get_singleton()->globalize_path(directory);
    std::error_code ec;
    const auto path = std::filesystem::u8path(absolute.utf8().get_data());
    std::filesystem::create_directories(path, ec);
    if (ec) { fail("Cannot create world directory."); return false; }
    // Metadata is embedded and checked in every region: format, generation, seed, block table.
    _directory = absolute.utf8().get_data(); _seed = seed; _biome_layout = biome_layout; { std::lock_guard<std::mutex> state_guard(_state_mutex); _error = String(); }
    return true;
}
void AstraeonNativeStream::fail(const String &message) { std::lock_guard<std::mutex> guard(_state_mutex); _error = message; }
String AstraeonNativeStream::get_last_error() const { std::lock_guard<std::mutex> guard(_state_mutex); return _error; }
int64_t AstraeonNativeStream::get_saved_blocks() const { return _saved.load(); }
int64_t AstraeonNativeStream::get_loaded_blocks() const { return _loaded.load(); }
void AstraeonNativeStream::load_voxel_block(VoxelQueryData &q) { access(q, false); }
void AstraeonNativeStream::save_voxel_block(VoxelQueryData &q) { access(q, true); }
void AstraeonNativeStream::set_region_handle_limit(int limit) {
    std::lock_guard<std::mutex> guard(_mutex);
    _region_limit = size_t(std::max(1, std::min(limit, 256)));
    while (_regions.size() > _region_limit) {
        auto oldest = _regions.end();
        for (auto it = _regions.begin(); it != _regions.end(); ++it) {
            if (it->second.use_count() == 1 && (oldest == _regions.end() || it->second->last_use < oldest->second->last_use)) oldest = it;
        }
        if (oldest == _regions.end()) break;
        _regions.erase(oldest); ++_region_evictions;
    }
    _region_available.notify_all();
}
std::shared_ptr<AstraeonNativeStream::Region> AstraeonNativeStream::acquire_region(const std::string &key) {
    std::unique_lock<std::mutex> guard(_mutex);
    for (;;) {
        auto found = _regions.find(key);
        if (found != _regions.end()) {
            found->second->last_use = ++_region_clock; ++_region_hits;
            return found->second;
        }
        if (_regions.size() < _region_limit) {
            auto region = std::make_shared<Region>();
            region->last_use = ++_region_clock;
            _regions.emplace(key, region); ++_region_misses;
            return region;
        }
        auto oldest = _regions.end();
        for (auto it = _regions.begin(); it != _regions.end(); ++it) {
            if (it->second.use_count() == 1 && (oldest == _regions.end() || it->second->last_use < oldest->second->last_use)) oldest = it;
        }
        if (oldest != _regions.end()) { _regions.erase(oldest); ++_region_evictions; }
        else _region_available.wait(guard);
    }
}
void AstraeonNativeStream::release_region(std::shared_ptr<Region> &region) {
    std::lock_guard<std::mutex> guard(_mutex);
    region.reset();
    _region_available.notify_all();
}
void AstraeonNativeStream::access(VoxelQueryData &q, bool writing) {
    const auto started = std::chrono::steady_clock::now();
    struct Timing {
        std::chrono::steady_clock::time_point start;
        std::atomic<int64_t> &duration, &count;
        ~Timing() { duration += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count(); ++count; }
    } timing{started, writing ? _save_usec : _load_usec, writing ? _save_requests : _load_requests};
    q.result = RESULT_ERROR;
    if (!get_last_error().is_empty()) return; // Sticky failure: never silently regenerate corrupted data.
    if (_directory.empty() || q.lod_index != 0 || q.voxel_buffer.get_size() != Vector3i(16,16,16)) {
        fail("Stream requires an open world and a 16-cube LOD0 section."); return;
    }
    const auto pos = q.position_in_blocks;
    const int rx = floor4(pos.x), ry = floor4(pos.y), rz = floor4(pos.z);
    const int index = (pos.x - rx * 4) + 4 * ((pos.y - ry * 4) + 4 * (pos.z - rz * 4));
    const auto path = std::filesystem::u8path(_directory) / (std::to_string(rx) + "_" + std::to_string(ry) + "_" + std::to_string(rz) + ".avr");
    auto region = acquire_region(path.string());
    struct Lease {
        AstraeonNativeStream &owner; std::shared_ptr<Region> &region;
        ~Lease() { owner.release_region(region); }
    } lease{*this, region};
    std::lock_guard<std::mutex> region_guard(region->mutex);
    if (!get_last_error().is_empty()) return;
    FILE *file = region->file;
    if (file == nullptr) {
        std::error_code ec;
        const bool exists = std::filesystem::exists(path, ec);
        if (ec) { fail("Cannot inspect region."); return; }
        if (!exists && !writing) { q.result = RESULT_BLOCK_NOT_FOUND; return; }
        file = open_file(path, !exists);
        if (!file) { fail("Cannot open region."); return; }
        setvbuf(file, nullptr, _IONBF, 0);
        region->file = file;
    std::array<unsigned char, HEADER> expected{};
    memcpy(expected.data(), "ASTRAEON", 8);
    put32(expected.data()+8, 3); // Exact format version.
    put32(expected.data()+12, 2); // Exact generator version.
    put32(expected.data()+16, uint32_t(_seed));
    put32(expected.data()+20, uint32_t(_biome_layout));
    put32(expected.data()+24, 0); // IDs may append; registry validates logical contracts.
    memcpy(expected.data()+32, _world_id.utf8().get_data(), 32);
    if (!exists) {
        if (fwrite(expected.data(), 1, HEADER, file) != HEADER || !sync_file(file)) { fail("Region header write failed."); return; }
    } else {
        std::array<unsigned char, HEADER> actual{};
        if (fread(actual.data(), 1, HEADER, file) != HEADER || actual != expected) { fail("Unsupported or damaged region metadata/seed/block table."); return; }
    }
    }
    Record records[2]{};
    const long offset = long(HEADER + size_t(index) * RECORD * 2);
    for (int slot = 0; slot < 2; ++slot) {
        if (fseek(file, offset + long(slot * RECORD), SEEK_SET) != 0) { fail("Region seek failed."); return; }
        fread(records[slot].data(), 1, RECORD, file);
        if (ferror(file)) { fail("Region read failed."); return; }
        clearerr(file);
    }
    const bool a = valid(records[0]), b = valid(records[1]);
    int newest = !a ? (b ? 1 : -1) : (!b || get32(records[0].data()) >= get32(records[1].data()) ? 0 : 1);
    if (newest < 0 && (!empty(records[0]) || !empty(records[1]))) { fail("Both section records failed checksum; recovery unavailable."); return; }
    if (!writing) {
        if (newest < 0) { q.result = RESULT_BLOCK_NOT_FOUND; return; }
        const auto &record = records[newest];
        for (int z = 0; z < 16; ++z) for (int x = 0; x < 16; ++x) for (int y = 0; y < 16; ++y) {
            const size_t i = 12 + 2 * (y + 16 * (x + 16 * z));
            const unsigned value = unsigned(record[i]) | (unsigned(record[i+1]) << 8);
            if (value >= uint64_t(_state_count)) { fail("Section contains an unsupported block ID."); return; }
            q.voxel_buffer.set_voxel(value, x, y, z, VoxelBuffer::CHANNEL_TYPE);
        }
        q.voxel_buffer.compress_uniform_channels(); ++_loaded; q.result = RESULT_BLOCK_FOUND; return;
    }
    if (q.generated_cache && newest >= 0) { q.result = RESULT_BLOCK_FOUND; return; }
    if (q.data_revision != 0) {
        std::lock_guard<std::mutex> guard(_mutex);
        auto found = _saved_revisions.find(path.string());
        if (found != _saved_revisions.end() && found->second[index] >= q.data_revision) {
            q.result = RESULT_BLOCK_FOUND; return;
        }
    }
    Record next{};
    const uint32_t sequence = newest < 0 ? 1 : get32(records[newest].data()) + 1;
    if (!sequence) { fail("Section sequence exhausted."); return; }
    put32(next.data(), sequence); put32(next.data()+4, 4096);
    for (int z = 0; z < 16; ++z) for (int x = 0; x < 16; ++x) for (int y = 0; y < 16; ++y) {
        const uint64_t value = q.voxel_buffer.get_voxel(x, y, z, VoxelBuffer::CHANNEL_TYPE);
        if (value >= uint64_t(_state_count)) { fail("Cannot persist an unsupported block ID."); return; }
        const size_t i = 12 + 2 * (y + 16 * (x + 16 * z));
        next[i] = static_cast<unsigned char>(value); next[i+1] = static_cast<unsigned char>(value >> 8);
    }
    put32(next.data() + RECORD - 4, crc(next.data(), RECORD - 4));
    const int slot = newest == 0 ? 1 : 0;
    if (fseek(file, offset + long(slot * RECORD), SEEK_SET) != 0 || fwrite(next.data(), 1, RECORD, file) != RECORD || !sync_file(file)) {
        fail("Section durable write failed; previous record retained."); return;
    }
    if (q.data_revision != 0) {
        std::lock_guard<std::mutex> guard(_mutex);
        _saved_revisions[path.string()][index] = q.data_revision;
    }
    ++_saved; q.result = RESULT_BLOCK_FOUND;
}
Dictionary AstraeonNativeStream::get_metrics() const {
    std::lock_guard<std::mutex> guard(_mutex);
    Dictionary d;
    d["save_revision_bytes"] = int64_t(_saved_revisions.size() * (64 * sizeof(uint64_t) + sizeof(std::string)));
    d["region_handles"] = int64_t(_regions.size());
    d["region_handle_limit"] = int64_t(_region_limit);
    d["region_hits"] = _region_hits.load(); d["region_misses"] = _region_misses.load();
    d["region_evictions"] = _region_evictions.load();
    d["saved_blocks"] = _saved.load(); d["loaded_blocks"] = _loaded.load();
    d["save_requests"] = _save_requests.load(); d["load_requests"] = _load_requests.load();
    d["save_usec"] = _save_usec.load(); d["load_usec"] = _load_usec.load();
    return d;
}
void AstraeonNativeStream::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_region_handle_limit", "limit"), &AstraeonNativeStream::set_region_handle_limit);
    ClassDB::bind_method(D_METHOD("get_metrics"), &AstraeonNativeStream::get_metrics);
    ClassDB::bind_method(D_METHOD("open_world", "directory", "seed", "biome_layout", "state_keys", "world_id"), &AstraeonNativeStream::open_world);
    ClassDB::bind_method(D_METHOD("get_last_error"), &AstraeonNativeStream::get_last_error);
    ClassDB::bind_method(D_METHOD("get_saved_blocks"), &AstraeonNativeStream::get_saved_blocks);
    ClassDB::bind_method(D_METHOD("get_loaded_blocks"), &AstraeonNativeStream::get_loaded_blocks);
}
}
