# ABOUTME: Tests XS BOOT block generation with feature class C API.
# ABOUTME: Validates forward declarations, field registration, and new() re-installation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::XS;
use File::Temp qw(tempfile);

# Build test source with a minimal class
my $source = q{use 5.42.0;
use utf8;

class TestClass {
    field $name :param :reader;
    field $age :param;
    field $count :param = 0;
    field $active :param = 1;

    method greet() {
        return "Hello";
    }
}
};

# Write source to temp file
my ($fh, $filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh $source;
close $fh;

# Set up grammar and parse file to IR
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSFeatureClassTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my $ir = parse_file_ir($gen_grammar, $filename);
ok(defined $ir, 'parse produces IR');

SKIP: {
    skip 'no IR', 19 unless defined $ir;

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'TestClass');
    my $xs_output = $target->generate($ir);

    # Test 2: Forward declarations present
    like($xs_output, qr/extern void Perl_class_setup_stash/,
        'XS contains class_setup_stash forward declaration');
    like($xs_output, qr/extern void Perl_class_seal_stash/,
        'XS contains class_seal_stash forward declaration');
    like($xs_output, qr/extern void Perl_class_prepare_initfield_parse/,
        'XS contains class_prepare_initfield_parse forward declaration');
    like($xs_output, qr/extern void Perl_class_apply_attributes/,
        'XS contains class_apply_attributes forward declaration');

    # Test 3: Static variable for original_new
    like($xs_output, qr/static CV \*TestClass_original_new = NULL;/,
        'XS contains static CV declaration for original_new');

    # Test 4: BOOT block present
    like($xs_output, qr/BOOT:/,
        'XS contains BOOT block');

    # Test 5: BOOT block contains class_setup_stash
    like($xs_output, qr/BOOT:.*Perl_class_setup_stash/s,
        'BOOT block contains class_setup_stash call');

    # Test 6: BOOT block contains PL_curstash save/restore
    like($xs_output, qr/HV \*old_stash = PL_curstash;.*PL_curstash = old_stash;/s,
        'BOOT block saves and restores PL_curstash');

    # Test 7: BOOT block contains field registration
    like($xs_output, qr/Perl_class_prepare_initfield_parse.*pad_add_name_pvs.*"\$name"/s,
        'BOOT block registers $name field');
    like($xs_output, qr/Perl_class_prepare_initfield_parse.*pad_add_name_pvs.*"\$age"/s,
        'BOOT block registers $age field');

    # Test 8: BOOT block contains class_seal_stash
    like($xs_output, qr/Perl_class_seal_stash/,
        'BOOT block contains class_seal_stash call');

    # Test 9: BOOT block contains new() re-installation sequence
    like($xs_output, qr/gv_fetchmethod.*TestClass_original_new.*GvCV_set.*newXS/s,
        'BOOT block contains new() re-installation sequence');

    # Test 10-16: Shadow constructor with param extraction
    like($xs_output, qr/call_sv\(\(SV\*\)TestClass_original_new, G_SCALAR\)/,
        'shadow new() calls original_new via call_sv');
    like($xs_output, qr/ObjectFIELDS\(obj\)/,
        'shadow new() uses ObjectFIELDS for indexed access');
    like($xs_output, qr/bool got_name = FALSE/,
        'shadow new() tracks required param name');
    like($xs_output, qr/bool got_age = FALSE/,
        'shadow new() tracks required param age');
    like($xs_output, qr/strEQ\(key, "name"\)/,
        'shadow new() matches name param with strEQ');
    like($xs_output, qr/strEQ\(key, "age"\)/,
        'shadow new() matches age param with strEQ');
    like($xs_output, qr/if \(!got_name\) croak/,
        'shadow new() validates required name param');

    # Test 17-19: Default value application for optional params
    like($xs_output, qr/strEQ\(key, "count"\)/,
        'shadow new() matches optional count param with strEQ');
    like($xs_output, qr/if \(!got_count\).*sv_setiv\(fields\[2\], 0\)/s,
        'shadow new() applies default 0 for count');
    like($xs_output, qr/if \(!got_active\).*sv_setiv\(fields\[3\], 1\)/s,
        'shadow new() applies default 1 for active');
}

done_testing();
