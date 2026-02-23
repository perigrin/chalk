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
    field $age :param :writer;
    field $count :param = 0;
    field $active :param = 1;

    method greet() {
        return "Hello";
    }

    method greet_name() {
        return "Hello, $name";
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

my ($ir, $sa, $sem_ctx) = parse_file_ir($gen_grammar, $filename);
ok(defined $ir, 'parse produces IR');

SKIP: {
    skip 'no IR', 32 unless defined $ir;

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'TestClass');
    my $xs_output = $target->generate_with_cfg($ir, $sa, $sem_ctx);

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

    # Test 20-23: Field access using ObjectFIELDS (Component C)
    unlike($xs_output, qr/hv_fetch\(hash, "name"/,
        'field access does NOT use hv_fetch for name field');
    like($xs_output, qr/ObjectFIELDS\(SvRV\(self\)\)\[0\]/,
        'field access uses ObjectFIELDS[0] for name field');

    # Test 24-25: Field reader accessor uses ObjectFIELDS
    unlike($xs_output, qr/name\(self\).*hv_fetch\(hash, "name"/s,
        'name() reader does NOT use hv_fetch');
    like($xs_output, qr/name\(self\).*newSVsv\(ObjectFIELDS\(SvRV\(self\)\)\[0\]\)/s,
        'name() reader uses ObjectFIELDS[0]');

    # Test 26: Method body no longer requires hash = (HV*)SvRV(self) for field-only methods
    # Note: greet() is field-free so it won't have hash var; we'll test with a field-using method
    # For now, check that name() reader doesn't need hash var
    unlike($xs_output, qr/name\(self\).*HV \*hash = \(HV\*\)SvRV\(self\)/s,
        'name() reader does NOT need hash variable');

    # Test 27-28: Interpolated string with field uses ObjectFIELDS
    unlike($xs_output, qr/greet_name.*hv_fetch\(hash, "name"/s,
        'greet_name() interpolation does NOT use hv_fetch for name field');
    like($xs_output, qr/greet_name.*ObjectFIELDS\(SvRV\(self\)\)\[0\]/s,
        'greet_name() interpolation uses ObjectFIELDS[0] for name field');

    # Test 29-32: Writer accessor generation for :writer fields
    like($xs_output, qr/set_age\(self, value\)/,
        'XS contains set_age writer method signature');
    like($xs_output, qr/void\s+set_age\(self, value\)/,
        'set_age writer returns void');
    like($xs_output, qr/SV \*self.*SV \*value/s,
        'set_age writer has self and value parameters');
    like($xs_output, qr/sv_setsv\(ObjectFIELDS\(SvRV\(self\)\)\[1\], value\)/,
        'set_age writer uses sv_setsv with ObjectFIELDS[1]');
}

# Test inheritance support (Component E)
my $inherit_source = q{use 5.42.0;
use utf8;

class Dog :isa(Animal) {
    field $breed :param :reader;
}
};

my ($inherit_fh, $inherit_filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $inherit_fh $inherit_source;
close $inherit_fh;

my ($inherit_ir, $inherit_sa, $inherit_sem_ctx) = parse_file_ir($gen_grammar, $inherit_filename);
ok(defined $inherit_ir, 'parse inheritance class produces IR');

SKIP: {
    skip 'no inheritance IR', 5 unless defined $inherit_ir;

    my $inherit_target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Dog');
    my $inherit_xs = $inherit_target->generate_with_cfg($inherit_ir, $inherit_sa, $inherit_sem_ctx);

    # Test 33: BOOT block contains class_apply_attributes with isa(Animal)
    like($inherit_xs, qr/class_apply_attributes.*isa\(Animal\)/s,
        'BOOT block contains class_apply_attributes with isa(Animal)');

    # Test 34: isa step comes after class_setup_stash
    like($inherit_xs, qr/class_setup_stash.*class_apply_attributes/s,
        'class_apply_attributes comes after class_setup_stash');

    # Test 35: isa step comes before class_seal_stash
    like($inherit_xs, qr/class_apply_attributes.*class_seal_stash/s,
        'class_apply_attributes comes before class_seal_stash');

    # Test 36: Verify exact optree construction (OP_CONST with "isa(Animal)")
    like($inherit_xs, qr/newSVpvs\("isa\(Animal\)"\)/,
        'isa attribute uses newSVpvs with literal "isa(Animal)"');

    # Test 37: No our @ISA in output
    unlike($inherit_xs, qr/our\s+\@ISA/,
        'no our @ISA in XS output (inheritance via class_apply_attributes)');
}

# Test eval_pv fallback for unsupported methods (Component G)
my $fallback_source = q{use 5.42.0;
use utf8;

class Calculator {
    field $multiplier :param :reader;

    method multiply($x) {
        return $multiplier * $x;
    }

    method check_type($obj) {
        return $obj isa Calculator;
    }

    method call_coderef($f) {
        return $f->($self);
    }
}
};

my ($fallback_fh, $fallback_filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fallback_fh $fallback_source;
close $fallback_fh;

my ($fallback_ir, $fallback_sa, $fallback_sem_ctx) = parse_file_ir($gen_grammar, $fallback_filename);
ok(defined $fallback_ir, 'parse class with unsupported methods produces IR');

SKIP: {
    skip 'no fallback IR', 8 unless defined $fallback_ir;

    my $fallback_target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Calculator');
    my $fallback_xs = $fallback_target->generate_with_cfg($fallback_ir, $fallback_sa, $fallback_sem_ctx);

    # Test 38: multiply() currently uses eval_pv fallback because IR doesn't properly
    # resolve field access in return expressions yet. This will be fixed in a future component.
    unlike($fallback_xs, qr/SV \*\s+multiply\(self, x\)/,
        'multiply() NOT emitted as XSUB (field access in expression not yet supported)');
    like($fallback_xs, qr/eval_pv\("sub Calculator::multiply/,
        'multiply() uses eval_pv fallback for now');

    # Test 39: check_type() also needs fallback because $obj param access broken in IR
    unlike($fallback_xs, qr/SV \*\s+check_type\(self, obj\)/,
        'check_type() NOT emitted as XSUB (param access in expression not yet supported)');
    like($fallback_xs, qr/eval_pv\("sub Calculator::check_type/,
        'check_type() uses eval_pv fallback for now');

    # Test 40: call_coderef() has unsupported construct - should use eval_pv fallback
    unlike($fallback_xs, qr/SV \*\s+call_coderef\(self, f\)/,
        'call_coderef() NOT emitted as XSUB (coderef invocation unsupported)');
    like($fallback_xs, qr/eval_pv\("sub Calculator::call_coderef/,
        'call_coderef() emitted as eval_pv fallback in BOOT block');

    # Test 41: Verify eval_pv call is in BOOT block
    like($fallback_xs, qr/BOOT:.*eval_pv\("sub Calculator::call_coderef/s,
        'eval_pv fallback call is in BOOT block');

    # Test 42: Verify eval_pv contains method signature stub
    like($fallback_xs, qr/eval_pv\("sub Calculator::call_coderef \{[^}]*\}"/,
        'eval_pv fallback contains method body stub');
}

done_testing();
