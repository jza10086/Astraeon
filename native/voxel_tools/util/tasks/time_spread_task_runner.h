#ifndef ZYLANN_TIME_SPREAD_TASK_RUNNER_H
#define ZYLANN_TIME_SPREAD_TASK_RUNNER_H

#include "../containers/fixed_array.h"
#include "../containers/span.h"
#include "../containers/std_queue.h"
#include "../thread/mutex.h"
#include <cstdint>
#include <string>

namespace zylann {

struct TimeSpreadTaskContext {
	// If this is set to `true` by a task,
	// it will be re-scheduled to run again, the next time the runner is processed.
	// Otherwise, the task will be destroyed after it runs.
	bool postpone = false;
};

class ITimeSpreadTask {
public:
	virtual ~ITimeSpreadTask() {}
	virtual void run(TimeSpreadTaskContext &ctx) = 0;
    // Names have static storage so diagnostic capture remains safe after task deletion.
    virtual const char *get_debug_name() const {return "TimeSpreadTask";}
};

// Runs tasks in the caller thread, within a time budget per call. Kind of like coroutines.
class TimeSpreadTaskRunner {
public:
	enum Priority { //
		PRIORITY_NORMAL = 0,
		PRIORITY_LOW = 1,
		PRIORITY_COUNT
	};

	~TimeSpreadTaskRunner();

	// Pushing is thread-safe.
	void push(ITimeSpreadTask *task, Priority priority = PRIORITY_NORMAL);
	void push(Span<ITimeSpreadTask *> tasks, Priority priority = PRIORITY_NORMAL);

	void process(uint64_t time_budget_usec);
	void flush();
	unsigned int get_pending_count() const;
    uint64_t get_peak_task_usec() const {return _peak_task_usec;}
    const char *get_peak_task_name() const {return _peak_task_name.c_str();}

private:
    struct Entry {ITimeSpreadTask *task;uint64_t queued_usec;};
	struct Queue {
		StdQueue<Entry> tasks;
		// TODO Optimization: naive thread safety. Should be enough for now.
		BinaryMutex tasks_mutex;
	};
	FixedArray<Queue, PRIORITY_COUNT> _queues;
    uint64_t _peak_task_usec=0;
    std::string _peak_task_name;
};

} // namespace zylann

#endif // ZYLANN_TIME_SPREAD_TASK_RUNNER_H
