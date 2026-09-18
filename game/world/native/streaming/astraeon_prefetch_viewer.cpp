#include "astraeon_prefetch_viewer.h"
#include "util/godot/core/class_db.h"
#include <algorithm>
namespace zylann::voxel {
AstraeonPrefetchViewer::AstraeonPrefetchViewer() {
    set_requires_visuals(false);
    set_requires_collisions(false);
    set_view_distance(48);
    set_view_distance_vertical_ratio(2.f / 3.f);
    set_process(true);
}
void AstraeonPrefetchViewer::set_prediction_seconds(double value) { _seconds = std::clamp(value, 0.0, 2.0); }
void AstraeonPrefetchViewer::_notification(int what) {
    if (what == NOTIFICATION_EXIT_TREE) { _initialized = false; return; }
    if (what != NOTIFICATION_PROCESS) return;
    Node3D *target = Object::cast_to<Node3D>(get_parent());
    if (!target) return;
    const Vector3 current = target->get_global_position();
    const double delta = get_process_delta_time();
    if (!_initialized || delta <= 0.0 || current.distance_to(_previous) > 128.0) {
        _velocity = Vector3(); _initialized = true;
    } else {
        const Vector3 measured = (current - _previous) / delta;
        // Stop and direction reversals invalidate the old prediction immediately.
        if (measured.length_squared() < 0.01 || measured.dot(_velocity) < 0.0) _velocity = measured;
        else _velocity = _velocity.lerp(measured, std::min(delta * 8.0, 1.0));
    }
    _previous = current;
    Vector3 lead = _velocity * _seconds;
    lead.y = 0.0;
    if (lead.length() > 48.0) lead = lead.normalized() * 48.0;
    set_global_position(current + lead);
}
void AstraeonPrefetchViewer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_prediction_seconds", "value"), &AstraeonPrefetchViewer::set_prediction_seconds);
    ClassDB::bind_method(D_METHOD("get_prediction_seconds"), &AstraeonPrefetchViewer::get_prediction_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "prediction_seconds", PROPERTY_HINT_RANGE, "0,2,0.05"), "set_prediction_seconds", "get_prediction_seconds");
}
}
