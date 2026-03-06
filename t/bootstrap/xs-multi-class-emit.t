# ABOUTME: Tests multi-class XS emission into a single .xs file.
# ABOUTME: Verifies cross-class direct calls, consolidated BOOT, and MODULE sections.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSMultiEmit') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

use File::Temp qw(tempfile);

# --- Class A: has a method that class B will call ---
my ($fh_a, $file_a) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_a <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class Helper {
    field $factor :param :reader;

    method compute($x) {
        return $x;
    }
}
PERL
close $fh_a;

# --- Class B: calls method on self and has a field ---
my ($fh_b, $file_b) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_b <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class Worker {
    field $name :param :reader;

    method process($input) {
        return $input;
    }

    method run($data) {
        my $result = $self->process($data);
        return $result;
    }
}
PERL
close $fh_b;

my ($ir_a, $sa_a, $ctx_a, $cfg_a) = eval { parse_file_ir($gen, $file_a) };
ok(defined $ir_a, 'Helper class parses') or BAIL_OUT("Parse failed: $@");

my ($ir_b, $sa_b, $ctx_b, $cfg_b) = eval { parse_file_ir($gen, $file_b) };
ok(defined $ir_b, 'Worker class parses') or BAIL_OUT("Parse failed: $@");

# --- Register both classes ---
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg->register('Helper', {
    ir => $ir_a, sa => $sa_a, ctx => $ctx_a, uses => [],
});
$reg->register('Worker', {
    ir => $ir_b, sa => $sa_b, ctx => $ctx_b, uses => [],
});

# --- Test 1: generate_multi_class exists and produces output ---
my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::MultiEmit',
    class_registry => $reg,
);

can_ok($xs, 'generate_multi_class');
my $code = eval { $xs->generate_multi_class([
    { class_name => 'Helper', ir => $ir_a, sa => $sa_a, ctx => $ctx_a, cfg_snapshot => $cfg_a },
    { class_name => 'Worker', ir => $ir_b, sa => $sa_b, ctx => $ctx_b, cfg_snapshot => $cfg_b },
]) };
ok(defined $code, 'generate_multi_class produces output')
    or BAIL_OUT("Multi-class gen failed: $@");

# --- Test 2: Multiple MODULE sections ---
my @module_sections = ($code =~ /^MODULE\s*=/mg);
is(scalar @module_sections, 2, 'two MODULE sections emitted');

# --- Test 3: Both class slugs appear in helpers ---
like($code, qr/_impl_helper_compute\(pTHX_/,
    'Helper class helpers use helper_ slug');
like($code, qr/_impl_worker_process\(pTHX_/,
    'Worker class helpers use worker_ slug');
like($code, qr/_impl_worker_run\(pTHX_/,
    'Worker class run helper uses worker_ slug');

# --- Test 4: Self-calls within Worker use worker_ slug ---
like($code, qr/_impl_worker_process\(aTHX_\s*self/,
    'self->process() within Worker uses _impl_worker_process');

# --- Test 5: Only ONE BOOT block ---
my @boot_blocks = ($code =~ /^BOOT:/mg);
is(scalar @boot_blocks, 1, 'exactly one BOOT block in multi-class output');

# --- Test 6: BOOT contains setup for both classes ---
my ($boot_section) = $code =~ /(BOOT:.*)/s;
like($boot_section, qr/gv_stashpv\("Helper"/s,
    'BOOT sets up Helper class');
like($boot_section, qr/gv_stashpv\("Worker"/s,
    'BOOT sets up Worker class');

# --- Test 7: Single preamble (only one set of #include) ---
my @includes = ($code =~ /#include "EXTERN\.h"/g);
is(scalar @includes, 1, 'single preamble — one #include "EXTERN.h"');

done_testing();
