#include <stdio.h>
#include <ruby.h>
#include <ruby/version.h>

int main(int argc, char **argv)
{
    int state = 0;
    VALUE result;

    ruby_sysinit(&argc, &argv);
    RUBY_INIT_STACK;
    if (ruby_setup() != 0) {
        fputs("ruby_setup failed\n", stderr);
        return 1;
    }

    ruby_script("rubyos-embed-probe");
    result = rb_eval_string_protect(
        "module RubyOS; class Kernel; def self.probe = :ruby_owns_the_machine; end; end; "
        "RubyOS::Kernel.probe",
        &state);

    if (state != 0) {
        VALUE error = rb_errinfo();
        VALUE message = rb_funcall(error, rb_intern("full_message"), 0);
        fprintf(stderr, "%s", StringValueCStr(message));
        ruby_cleanup(state);
        return 1;
    }

    printf("embedded %s\n", ruby_description);
    printf("kernel probe: %s\n", rb_id2name(SYM2ID(result)));
    return ruby_cleanup(0);
}
