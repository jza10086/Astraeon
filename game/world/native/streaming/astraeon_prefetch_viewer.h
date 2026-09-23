#pragma once
#include "terrain/voxel_viewer.h"
namespace zylann::voxel {
// Attach to the player. This viewer requests data ahead; visual/collision viewers stay at the player.
class AstraeonPrefetchViewer : public VoxelViewer {
    GDCLASS(AstraeonPrefetchViewer, VoxelViewer)
public:
    AstraeonPrefetchViewer();
    void set_prediction_seconds(double value);
    void set_max_prediction_distance(double value);
    double get_max_prediction_distance() const {return _max_distance;}
    void set_cache_pressure(bool pressure) { _pressure=pressure; }
    double get_prediction_seconds() const { return _seconds; }
protected:
    void _notification(int what);
    static void _bind_methods();
private:
    Vector3 _previous;
    Vector3 _velocity;
    bool _initialized = false;
    double _seconds = 0.75, _max_distance = 48.0;
    bool _pressure = false;
};
}
