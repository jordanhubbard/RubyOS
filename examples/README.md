# RubyOS learning examples

RubyOS treats examples as a curriculum rather than a program dump. The
authoritative catalog is `RubyOS::Examples`: its immutable track and lesson
records are frozen into both guest architectures and mounted as readable source
under `/examples`.

From any `rubyos>` prompt:

```text
examples
examples start_here
example start_here/hello_kernel
example concurrency/fiber_mailbox
example concurrency/structured_tasks
cat /examples/concurrency/README.txt
```

The suggested path is `start_here`, `language`, `concurrency`, `storage`,
`networking`, `graphics`, `audio`, `web`, and `internals`; `demos` and `games`
then point into the graphical Apps catalog. Every runnable lesson starts with
its canonical `/examples/TRACK/NAME.rb` path and uses the real RubyOS objects.

The top-level scripts in this checkout are larger host-side integration
lessons. `curriculum.rb` executes every frozen lesson, while the subsystem
scripts exercise longer workflows using the same APIs.
