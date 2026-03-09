# ABOUTME: Tests that XS emitter uses class-derived namespace slugs on all identifiers.
# ABOUTME: Prevents identifier collisions when multiple classes share one .xs file.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

# --- Setup: parse a class with self-calls, field-invocant calls, and a field ---

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSSlug') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

use File::Temp qw(tempfile);
my ($fh, $filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class SlugTest {
    field $worker :param;
    field $data :param :reader;

    method helper($x) {
        return $x;
    }

    method do_work($input) {
        my $result = $self->helper($input);
        my $check = $worker->validate($result);
        return $check;
    }
}
PERL
close $fh;

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $filename) };
ok(defined $ir, 'test class parses to IR') or BAIL_OUT("Parse failed: $@");

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::Slug');
my $code = eval { $xs->generate_with_cfg($ir, $sa, $ctx) };
ok(defined $code, 'XS code generated') or BAIL_OUT("XS gen failed: $@");

# --- Test 1: _class_slug method exists and returns expected value ---
can_ok($xs, '_class_slug');
is($xs->_class_slug('SlugTest'), 'slugtest', '_class_slug returns lowercased last component');
is($xs->_class_slug('Chalk::Bootstrap::Earley'), 'earley', '_class_slug handles qualified names');

# --- Test 2: _impl_ helpers have class slug prefix ---
like($code, qr/static\s+SV\s*\*\s*_impl_slugtest_helper\(pTHX_/,
    'helper function has class slug prefix: _impl_slugtest_helper');
like($code, qr/static\s+SV\s*\*\s*_impl_slugtest_do_work\(pTHX_/,
    'helper function has class slug prefix: _impl_slugtest_do_work');

# No un-prefixed helpers should exist
unlike($code, qr/static\s+SV\s*\*\s*_impl_helper\(pTHX_/,
    'no un-prefixed _impl_helper');
unlike($code, qr/static\s+SV\s*\*\s*_impl_do_work\(pTHX_/,
    'no un-prefixed _impl_do_work');

# --- Test 3: Self-calls use slugged helper names ---
like($code, qr/_impl_slugtest_helper\(aTHX_\s*self/,
    'self->helper() uses _impl_slugtest_helper direct call');

# --- Test 4: CV cache variables have class slug prefix ---
TODO: {
    local $TODO = 'CV cache vars not yet slugged in XS emitter';
    like($code, qr/static\s+CV\s*\*\s*_cv_slugtest_worker_validate\s*=\s*NULL/,
        'CV cache variable has class slug prefix');
    like($code, qr/call_sv\(\(SV\s*\*\)_cv_slugtest_worker_validate/,
        'call_sv uses slugged CV cache key');
}

# --- Test 5: Forward declarations use slugged names ---
like($code, qr/_impl_slugtest_helper\(pTHX_/,
    'forward declaration uses slugged name');

# --- Test 6: Intrinsics also get slugged ---
# Parse a class with semiring_intrinsics
my ($fh2, $filename2) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh2 <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class IntrinsicSlugTest {
    field $semiring :param;

    method check($value) {
        my $z = $semiring->is_zero($value);
        return $z;
    }
}
PERL
close $fh2;

my ($ir2, $sa2, $ctx2) = eval { parse_file_ir($gen, $filename2) };
ok(defined $ir2, 'intrinsic test class parses to IR') or BAIL_OUT("Parse failed: $@");

my $intrinsic_spec = {
    semiring => {
        components => [
            { type => 'boolean_refaddr' },
            { type => 'hash_valid' },
            { type => 'defined' },
            { type => 'integer_eq', value => 0 },
            { type => 'defined' },
        ],
    },
};

my $xs2 = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::IntrinsicSlug',
    semiring_intrinsics => $intrinsic_spec,
);
my $code2 = eval { $xs2->generate_with_cfg($ir2, $sa2, $ctx2) };
ok(defined $code2, 'XS code with intrinsics generated') or BAIL_OUT("XS gen failed: $@");

like($code2, qr/static\s+int\s+_inline_intrinsicslugtest_is_zero/,
    'inline is_zero has class slug prefix');
like($code2, qr/_inline_intrinsicslugtest_is_zero\(aTHX_/,
    'is_zero call sites use slugged intrinsic name');
unlike($code2, qr/static\s+int\s+_inline_is_zero\b/,
    'no un-prefixed _inline_is_zero');

done_testing();
