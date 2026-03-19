# ABOUTME: Tests for Target::C emission pipeline using Boolean.pm as the input IR.
# ABOUTME: Verifies generate_c_files structure and that emitted C code contains all expected functions.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::C;

# === Phase 1: Set up grammar pipeline ===

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CTBool') };
ok(defined $gen, 'Phase 1: grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

# === Phase 2: Parse Boolean.pm to IR ===

my ($ir, $sa, $ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm')
};
ok(defined $ir, 'Phase 2: Boolean.pm parsed to IR')
    or BAIL_OUT("Cannot continue without IR: $@");

# === Phase 3: Construct Target::C ===

my $target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Chalk::Bootstrap::Semiring::Boolean')
};
ok(defined $target, 'Phase 3: Target::C constructed')
    or BAIL_OUT("Constructor failed: $@");
isa_ok($target, 'Chalk::Bootstrap::Perl::Target::C');
is($target->module_name(), 'Chalk::Bootstrap::Semiring::Boolean',
    'module_name reader returns correct value');

# === Phase 4: Call generate_c_files ===

my $result = eval { $target->generate_c_files($ir, $sa, $ctx) };
is($@, '', 'Phase 4: generate_c_files does not die')
    or BAIL_OUT("generate_c_files died: $@");
ok(defined $result, 'generate_c_files returns a defined value');

# === Phase 5: Verify result structure ===

is(ref($result), 'HASH', 'result is a hashref');

ok(exists $result->{files},                   'result has "files" key');
ok(exists $result->{exported_functions},      'result has "exported_functions" key');
ok(exists $result->{skipped_methods},         'result has "skipped_methods" key');
ok(exists $result->{anon_sub_registrations},  'result has "anon_sub_registrations" key');

is(ref($result->{files}), 'HASH',              '"files" is a hashref');
is(ref($result->{exported_functions}), 'ARRAY', '"exported_functions" is an arrayref');
is(ref($result->{skipped_methods}), 'ARRAY',    '"skipped_methods" is an arrayref');
is(ref($result->{anon_sub_registrations}), 'ARRAY', '"anon_sub_registrations" is an arrayref');

# The slug for Boolean is "boolean"
ok(exists $result->{files}{'boolean.c'}, '"files" has "boolean.c" key');
ok(exists $result->{files}{'boolean.h'}, '"files" has "boolean.h" key');

# === Phase 6: Verify content ===

my $c_src = $result->{files}{'boolean.c'};
ok(length($c_src) > 0, 'boolean.c is non-empty');
like($c_src, qr/boolean_is_zero/, 'boolean.c contains boolean_is_zero function');
like($c_src, qr/boolean_zero/,    'boolean.c contains boolean_zero function');
like($c_src, qr/boolean_one/,     'boolean.c contains boolean_one function');
like($c_src, qr/boolean_multiply/, 'boolean.c contains boolean_multiply function');
like($c_src, qr/boolean_add/,     'boolean.c contains boolean_add function');
unlike($c_src, qr/_impl_/, 'boolean.c has no _impl_ prefix');
unlike($c_src, qr/\bstatic\b[^*]*\bboolean_\w+\s*\(/, 'exported functions are not static');

my $h_src = $result->{files}{'boolean.h'};
ok(length($h_src) > 0, 'boolean.h is non-empty');
like($h_src, qr/boolean_is_zero/, 'boolean.h declares boolean_is_zero');
like($h_src, qr/#ifndef CHALK_BOOLEAN_H/, 'boolean.h has include guard');

# === Phase 7: Determinism check ===

my $result2 = eval { $target->generate_c_files($ir, $sa, $ctx) };
is($@, '', 'second generate_c_files call does not die');
is($result2->{files}{'boolean.c'}, $result->{files}{'boolean.c'}, 'deterministic .c output');
is($result2->{files}{'boolean.h'}, $result->{files}{'boolean.h'}, 'deterministic .h output');

done_testing;
