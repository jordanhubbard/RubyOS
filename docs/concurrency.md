# Fiber concurrency in RubyOS

RubyOS keeps CRuby on its GVL-owning bootstrap processor and schedules kernel
work cooperatively with `Fiber`. A task runs until it reaches an explicit
scheduling point: `yield_now`, `sleep_for`, `join`/`gather`, or an
`Async::Channel`, `Event`, or `Semaphore` wait. This makes shared Ruby objects
predictable without pretending the VM is preemptively thread-safe.

## Structured tasks and channels

`TaskGroup.open` scopes child tasks to a block. Results preserve task creation
order. The first child failure is raised in the supervisor and unfinished
siblings are killed before the scope exits.

```ruby
scheduler = RubyOS::Scheduler.new
jobs = RubyOS::Async::Channel.new(scheduler:, capacity: 2)

scheduler.spawn("supervisor") do
  results = RubyOS::Async::TaskGroup.open(scheduler) do |group|
    group.async("producer") do
      (1..5).each { |number| jobs << number }
      jobs.close
      :sent
    end

    group.async("consumer") do
      jobs.map { |number| number * number }
    end
  end
  # results == [:sent, [1, 4, 9, 16, 25]]
end

scheduler.run
```

A bounded channel applies backpressure when full and includes `Enumerable`, so
ordinary `map`, `filter_map`, and `each_with_object` pipelines work until the
producer closes it. Receiving from an empty closed channel raises
`Async::ClosedError`; enumeration treats that state as its normal end.

## Coordination and deadlines

`Async::Event` is a reusable set/clear latch. `Async::Semaphore` limits
concurrent entries and its `synchronize` method always releases through
`ensure`. A limit of one is the cooperative lock form.

All blocking operations accept `timeout_ms:`. Deadlines use the scheduler's
monotonic clock and raise `Scheduler::TimeoutError`. `Scheduler#join` returns
one task result; `gather` returns results in argument order and propagates a
failure without waiting for unrelated unfinished tasks.

These objects coordinate Ruby Fibers, not native CPU work. Use
`RubyOS::Concurrency.native_hash` and the bounded native-worker API for
explicitly C-safe work on application processors. CRuby objects never cross
that mailbox as concurrently mutable state.

## Explore it

From a RubyOS console:

```text
examples concurrency
example concurrency/fiber_mailbox
example concurrency/structured_tasks
cat /examples/concurrency/README.txt
tasks
```

`tasks` shows PID, state, and charged ticks. `kill PID` cancels a live task;
`reap PID` removes its terminal record. The same lifecycle is visible in System
Monitor and Ruby Inspector.
