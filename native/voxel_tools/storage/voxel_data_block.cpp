#include "voxel_data_block.h"
#include "../util/io/log.h"
#include "../util/string/format.h"

#include <atomic>

namespace zylann::voxel {
uint64_t VoxelDataBlock::next_revision() {
	static std::atomic<uint64_t> counter{0};
	return ++counter;
}

void VoxelDataBlock::set_modified(bool modified) {
	// #ifdef TOOLS_ENABLED
	// 	if (_modified == false && modified) {
	// 		ZN_PRINT_VERBOSE(format("Marking block {} as modified", size_t(this)));
	// 	}
	// #endif
	_modified = modified;
	if (modified) _revision = next_revision();
}

} // namespace zylann::voxel
