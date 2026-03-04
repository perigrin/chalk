# ABOUTME: Tests that XS emitter generates CV cache for field-invocant method calls.
# ABOUTME: Verifies $field->method() calls use lazy-resolved call_sv instead of call_method.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

# --- Setup: parse a class with a field used as method call invocant ---

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSCvCache') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

use File::Temp qw(tempfile);
my ($fh, $filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class CvCacheTest {
    field $worker :param;

    method do_work($input) {
        my $result = $worker->process($input);
        my $check = $worker->validate($result);
        return $check;
    }
}
PERL
close $fh;

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $filename) };
ok(defined $ir, 'test class parses to IR') or BAIL_OUT("Parse failed: $@");

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::CvCache');
my $code = eval { $xs->generate_with_cfg($ir, $sa, $ctx) };
ok(defined $code, 'XS code generated') or BAIL_OUT("XS gen failed: $@");

# --- Test 1: Static CV cache variables declared ---
like($code, qr/static\s+CV\s*\*\s*_cv_\w+_process\s*=\s*NULL/,
    'static CV cache variable for process() declared');

like($code, qr/static\s+CV\s*\*\s*_cv_\w+_validate\s*=\s*NULL/,
    'static CV cache variable for validate() declared');

# --- Test 2: CV cache declarations appear before MODULE line ---
my $module_pos = index($code, 'MODULE =');
my $cv_cache_pos = index($code, '_cv_');
ok($cv_cache_pos >= 0 && $module_pos >= 0, 'both CV cache and MODULE line exist');
ok($cv_cache_pos < $module_pos, 'CV cache declarations appear before MODULE line');

# --- Test 3: call_sv used instead of call_method for field methods ---
like($code, qr/call_sv\(\(SV\s*\*\)_cv_\w+_process/,
    'field->process() uses call_sv with cached CV');

like($code, qr/call_sv\(\(SV\s*\*\)_cv_\w+_validate/,
    'field->validate() uses call_sv with cached CV');

# --- Test 4: No call_method for cached field methods ---
my @cm_process = ($code =~ /call_method\("process"/g);
is(scalar @cm_process, 0,
    'no call_method("process") — uses CV cache instead');

my @cm_validate = ($code =~ /call_method\("validate"/g);
is(scalar @cm_validate, 0,
    'no call_method("validate") — uses CV cache instead');

# --- Test 5: Lazy resolution via gv_fetchmethod_autoload ---
like($code, qr/gv_fetchmethod_autoload/,
    'lazy CV resolution uses gv_fetchmethod_autoload');

# --- Test 6: Non-field method calls still use call_method ---
# Parse a class where method is called on a local variable (not a field)
my ($fh2, $filename2) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh2 <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class NoFieldCallTest {
    method do_work($input) {
        my $obj = $input;
        my $result = $obj->process();
        return $result;
    }
}
PERL
close $fh2;

my ($ir2, $sa2, $ctx2) = eval { parse_file_ir($gen, $filename2) };
ok(defined $ir2, 'no-field test class parses to IR') or BAIL_OUT("Parse failed: $@");

my $xs2 = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::NoFieldCall');
my $code2 = eval { $xs2->generate_with_cfg($ir2, $sa2, $ctx2) };
ok(defined $code2, 'no-field XS code generated') or BAIL_OUT("XS gen failed: $@");

# Non-field invocant should still use call_method (no CV cache)
my @cm2 = ($code2 =~ /call_method\("process"/g);
ok(scalar @cm2 > 0,
    'non-field $obj->process() still uses call_method');

# No CV cache variables should be emitted
unlike($code2, qr/static\s+CV\s*\*\s*_cv_/,
    'no CV cache variables for non-field invocants');

done_testing();
