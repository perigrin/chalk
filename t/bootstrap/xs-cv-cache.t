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

# --- Test 7: Semiring intrinsics - inline is_zero ---
# Parse a class with $semiring->is_zero($val) calls to test intrinsic inlining

my ($fh3, $filename3) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh3 <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class SemiringTest {
    field $semiring :param;

    method check_value($val) {
        if ($semiring->is_zero($val)) {
            return false;
        }
        return true;
    }

    method process($a, $b) {
        my $result = $semiring->multiply($a, $b);
        if ($semiring->is_zero($result)) {
            return $semiring->zero();
        }
        return $result;
    }
}
PERL
close $fh3;

my ($ir3, $sa3, $ctx3) = eval { parse_file_ir($gen, $filename3) };
ok(defined $ir3, 'semiring test class parses to IR') or BAIL_OUT("Parse failed: $@");

# Generate WITH semiring_intrinsics config
my $xs3 = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::SemiringIntrinsic',
    semiring_intrinsics => {
        semiring => {
            components => [
                { type => 'boolean_refaddr' },
                { type => 'hash_valid' },
                { type => 'defined' },
                { type => 'integer_eq', value => -1 },
                { type => 'defined' },
            ],
        },
    },
);
my $code3 = eval { $xs3->generate_with_cfg($ir3, $sa3, $ctx3) };
ok(defined $code3, 'XS code with semiring intrinsics generated')
    or BAIL_OUT("XS gen failed: $@");

# Test 7a: Static _inline_SLUG_is_zero function is emitted
like($code3, qr/static\s+int\s+_inline_semiringtest_is_zero/,
    'static _inline_semiringtest_is_zero function emitted');

# Test 7b: The inline function appears before MODULE line
{
    my $module_pos3 = index($code3, 'MODULE =');
    my $inline_pos3 = index($code3, '_inline_semiringtest_is_zero');
    ok($inline_pos3 >= 0 && $module_pos3 >= 0,
        'both _inline_semiringtest_is_zero and MODULE line exist');
    ok($inline_pos3 < $module_pos3,
        '_inline_semiringtest_is_zero appears before MODULE line');
}

# Test 7c: The inline function contains component checks
like($code3, qr/Component \[0\]: boolean_refaddr/,
    'inline is_zero has Boolean refaddr check');
like($code3, qr/hv_fetchs\([^,]+,\s*"valid"/,
    'inline is_zero has Precedence valid check');
like($code3, qr/SvIV\([^)]+\)\s*==\s*-1/,
    'inline is_zero has Structural == -1 check');
# Two !SvOK checks: TypeInference[2] and SemanticAction[4]
my @svok_checks = ($code3 =~ /!SvOK\(\*/g);
ok(scalar @svok_checks >= 2,
    'inline is_zero has at least 2 !SvOK checks (TI + SA)');

# Test 7d: is_zero call sites use intrinsic, not call_sv
unlike($code3, qr/call_sv\(\(SV\s*\*\)_cv_\w+_is_zero/,
    'no call_sv for is_zero — uses intrinsic instead');
like($code3, qr/_inline_semiringtest_is_zero\(aTHX_/,
    'is_zero call sites use _inline_semiringtest_is_zero intrinsic');

# Test 7e: Non-is_zero methods still use call_sv or call_method
# multiply() and zero() should NOT be inlined
like($code3, qr/(?:call_sv|call_method).*multiply|multiply.*(?:call_sv|call_method)/s,
    'multiply() still uses Perl dispatch (not inlined)');

# Test 7f: Without semiring_intrinsics, is_zero uses normal Perl dispatch
my $xs3_no_intrinsic = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::SemiringNoIntrinsic',
);
my $code3_no = eval { $xs3_no_intrinsic->generate_with_cfg($ir3, $sa3, $ctx3) };
ok(defined $code3_no, 'XS code without intrinsics generated');
unlike($code3_no, qr/static\s+int\s+_inline_\w+_is_zero/,
    'no _inline_SLUG_is_zero without semiring_intrinsics config');
like($code3_no, qr/call_method\("is_zero"|call_sv\(\(SV\s*\*\)_cv_\w+_is_zero/,
    'is_zero uses Perl dispatch when no intrinsics configured');

done_testing();
