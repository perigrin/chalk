# ABOUTME: Tests that XS emitter handles map { $_->method() } @array patterns.
# ABOUTME: Verifies topic binding ($_ = current element) inside map loop bodies.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Skip guards
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

# --- Step 1: Parse FilterComposite.pm to IR ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSMapMethodCall') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# Parse all needed classes — FilterComposite depends on the 5 semirings
my @class_files = (
    ['Chalk::Bootstrap::Semiring::Boolean',         'lib/Chalk/Bootstrap/Semiring/Boolean.pm'],
    ['Chalk::Bootstrap::Semiring::Precedence',      'lib/Chalk/Bootstrap/Semiring/Precedence.pm'],
    ['Chalk::Bootstrap::Semiring::TypeInference',   'lib/Chalk/Bootstrap/Semiring/TypeInference.pm'],
    ['Chalk::Bootstrap::Semiring::Structural',      'lib/Chalk/Bootstrap/Semiring/Structural.pm'],
    ['Chalk::Bootstrap::Semiring::SemanticAction',  'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm'],
    ['Chalk::Bootstrap::Semiring::FilterComposite', 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm'],
);

my %parsed;
for my $entry (@class_files) {
    my ($class_name, $file) = $entry->@*;
    my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $file) };
    ok(defined $ir, "$class_name parses to IR") or BAIL_OUT("Parse failed: $@");
    $parsed{$class_name} = { ir => $ir, sa => $sa, ctx => $ctx };
}

# --- Step 2: Register classes and generate multi-class XS ---
my @semiring_classes = map { $_->[0] } @class_files[0..4];
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();

for my $entry (@class_files) {
    my ($class_name, $file) = $entry->@*;
    next if $class_name eq 'Chalk::Bootstrap::Semiring::FilterComposite';
    $reg->register($class_name, {
        ir => $parsed{$class_name}{ir},
        sa => $parsed{$class_name}{sa},
        ctx => $parsed{$class_name}{ctx},
        uses => [],
    });
}
$reg->register('Chalk::Bootstrap::Semiring::FilterComposite', {
    ir => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{ir},
    sa => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{sa},
    ctx => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{ctx},
    uses => \@semiring_classes,
    composite_components => { semirings => \@semiring_classes },
});

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSMapMethodCall',
    class_registry => $reg,
);

my @entries = map {
    my $p = $parsed{$_->[0]};
    { class_name => $_->[0], ir => $p->{ir}, sa => $p->{sa}, ctx => $p->{ctx} }
} @class_files;

my $xs_code = eval { $xs->generate_multi_class(\@entries) };
ok(defined $xs_code, 'multi-class XS generation succeeds')
    or BAIL_OUT("XS gen failed: $@");

# --- Step 3: Verify FilterComposite zero/one use _impl_ helpers ---
# These methods are: [ map { $_->zero() } $semirings->@* ]
# They should compile to _impl_ helpers that iterate over the semirings
# array and call zero/one on each element.

like($xs_code, qr/_impl_filtercomposite_zero/,
    'FilterComposite zero compiles to _impl_ helper');

like($xs_code, qr/_impl_filtercomposite_one/,
    'FilterComposite one compiles to _impl_ helper');

# The map block should bind $_ (the topic) to each array element
# and call the method on it — NOT produce empty hashrefs
unlike($xs_code, qr/_impl_filtercomposite_zero[^}]*newRV_noinc\(\(SV\*\)newHV\(\)\)/,
    'zero does NOT produce empty hashrefs (map block was compiled)');

unlike($xs_code, qr/_impl_filtercomposite_one[^}]*newRV_noinc\(\(SV\*\)newHV\(\)\)/,
    'one does NOT produce empty hashrefs (map block was compiled)');

# The generated code should contain a call_method("zero") or _impl_ call
# inside the map loop for the zero method
like($xs_code, qr/_impl_filtercomposite_zero\(.*?call_method\("zero"/s,
    'zero map loop calls zero on each element');

like($xs_code, qr/_impl_filtercomposite_one\(.*?call_method\("one"/s,
    'one map loop calls one on each element');

# --- Step 4: Build and test at runtime ---
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

my $dist = eval { $xs->generate_distribution_multi_class(\@entries) };
ok(ref($dist) eq 'HASH', 'distribution generated')
    or BAIL_OUT("dist gen failed: $@");

my $tmpdir = tempdir(CLEANUP => 1);
for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    my $dir = dirname($full_path);
    make_path($dir) unless -d $dir;
    open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $wfh $dist->{$path};
    close $wfh;
}

{
    my $output = `cd "$tmpdir" && "$^X" -Ilib Build.PL 2>&1`;
    is($? >> 8, 0, 'Build.PL exits cleanly') or diag $output;
}
{
    my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
    my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
    is($? >> 8, 0, 'XS compiles without errors') or do {
        diag $output;
        done_testing();
        exit;
    };
}

# Load and test zero/one at runtime
unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
eval { require Test::XSMapMethodCall };
ok(!$@, 'XS module loads') or do {
    diag "Load error: $@";
    done_testing();
    exit;
};

# Create a FilterComposite with real semirings and test zero/one
my $semiring = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [
        Chalk::Bootstrap::Semiring::Boolean->new(),
        Chalk::Bootstrap::Semiring::Precedence->new(
            lookup => sub { return },
        ),
        Chalk::Bootstrap::Semiring::TypeInference->new(
            keyword_check  => sub { return false },
            builtin_lookup => sub { return },
        ),
        Chalk::Bootstrap::Semiring::Structural->new(),
        Chalk::Bootstrap::Semiring::SemanticAction->new(
            actions => undef,
        ),
    ],
);

my $zero = eval { $semiring->zero() };
ok(defined $zero, 'zero() returns a value') or diag "Error: $@";
is(ref($zero), 'ARRAY', 'zero() returns an arrayref');
is(scalar $zero->@*, 5, 'zero() has 5 elements (one per semiring)');

my $one = eval { $semiring->one() };
ok(defined $one, 'one() returns a value') or diag "Error: $@";
is(ref($one), 'ARRAY', 'one() returns an arrayref');
is(scalar $one->@*, 5, 'one() has 5 elements (one per semiring)');

# Verify the zero tuple is actually zero
ok($semiring->is_zero($zero), 'zero() produces a tuple that is_zero recognizes');

done_testing();
