# ABOUTME: Tests XS BOOT block generation with feature class C API.
# ABOUTME: Validates forward declarations, defop-based field registration, and attribute application.
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
    skip 'no IR', 28 unless defined $ir;

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'TestClass');
    my $xs_output = $target->generate_with_cfg($ir, $sa, $sem_ctx);

    # --- Forward declarations for class C API ---
    like($xs_output, qr/extern void Perl_class_setup_stash/,
        'XS contains class_setup_stash forward declaration');
    like($xs_output, qr/extern void Perl_class_prepare_initfield_parse/,
        'XS contains class_prepare_initfield_parse forward declaration');
    like($xs_output, qr/extern void Perl_class_set_field_defop/,
        'XS contains class_set_field_defop forward declaration');
    like($xs_output, qr/extern void Perl_class_apply_field_attributes/,
        'XS contains class_apply_field_attributes forward declaration');

    # --- BOOT block structure ---
    like($xs_output, qr/BOOT:/,
        'XS contains BOOT block');
    like($xs_output, qr/BOOT:.*Perl_class_setup_stash/s,
        'BOOT block contains class_setup_stash call');
    like($xs_output, qr/HV \*old_stash = PL_curstash;.*PL_curstash = old_stash;/s,
        'BOOT block saves and restores PL_curstash');

    # --- Seal is implicit via ENTER/LEAVE (no explicit seal_stash call) ---
    unlike($xs_output, qr/Perl_class_seal_stash/,
        'no explicit class_seal_stash (implicit via LEAVE)');

    # --- No shadow constructor (defop-based approach) ---
    unlike($xs_output, qr/static CV \*TestClass_original_new/,
        'no static CV for original_new (defop replaces shadow constructor)');
    unlike($xs_output, qr/gv_fetchmethod.*original_new/s,
        'no new() re-installation sequence');

    # --- Field registration via defop API ---
    like($xs_output, qr/class_prepare_initfield_parse.*pad_add_name_pvs.*"\$name"/s,
        'BOOT block registers $name field');
    like($xs_output, qr/class_prepare_initfield_parse.*pad_add_name_pvs.*"\$age"/s,
        'BOOT block registers $age field');
    like($xs_output, qr/class_prepare_initfield_parse.*pad_add_name_pvs.*"\$count"/s,
        'BOOT block registers $count field');
    like($xs_output, qr/class_prepare_initfield_parse.*pad_add_name_pvs.*"\$active"/s,
        'BOOT block registers $active field');

    # --- Field attributes applied via class_apply_field_attributes ---
    like($xs_output, qr/newSVpvs\("param"\).*class_apply_field_attributes/s,
        ':param attribute applied via class_apply_field_attributes');
    like($xs_output, qr/newSVpvs\("reader"\).*class_apply_field_attributes/s,
        ':reader attribute applied via class_apply_field_attributes');
    like($xs_output, qr/newSVpvs\("writer"\).*class_apply_field_attributes/s,
        ':writer attribute applied via class_apply_field_attributes');

    # --- Default values via class_set_field_defop ---
    like($xs_output, qr/newSViv\(0\).*class_set_field_defop/s,
        '$count default 0 applied via class_set_field_defop');
    like($xs_output, qr/newSViv\(1\).*class_set_field_defop/s,
        '$active default 1 applied via class_set_field_defop');

    # --- ENTER/LEAVE scoping for each field ---
    # Each field has its own ENTER/LEAVE around prepare_initfield_parse
    my @enter_count = ($xs_output =~ /\bENTER\b/g);
    my @leave_count = ($xs_output =~ /\bLEAVE\b/g);
    ok(scalar(@enter_count) >= 5, 'at least 5 ENTER blocks (1 outer + 4 fields)');
    is(scalar(@enter_count), scalar(@leave_count), 'ENTER/LEAVE balanced');

    # --- Field access using ObjectFIELDS ---
    unlike($xs_output, qr/hv_fetch\(hash, "name"/,
        'field access does NOT use hv_fetch for name field');
    like($xs_output, qr/ObjectFIELDS\(SvRV\(self\)\)\[0\]/,
        'field access uses ObjectFIELDS[0] for name field');

    # --- No hash variable needed for field-only methods ---
    unlike($xs_output, qr/HV \*hash = \(HV\*\)SvRV\(self\)/,
        'no hash variable needed (ObjectFIELDS used instead)');

    # --- Interpolated string with field uses ObjectFIELDS ---
    unlike($xs_output, qr/greet_name.*hv_fetch\(hash, "name"/s,
        'greet_name() interpolation does NOT use hv_fetch for name field');
    like($xs_output, qr/greet_name.*ObjectFIELDS\(SvRV\(self\)\)\[0\]/s,
        'greet_name() interpolation uses ObjectFIELDS[0] for name field');

    # --- No reader/writer XSUBs emitted (seal_stash auto-generates them) ---
    unlike($xs_output, qr/^SV \*\nname\(self\)/m,
        'no explicit name() reader XSUB (auto-generated by seal)');
}

# Test inheritance support
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

    # BOOT block contains class_apply_attributes with isa(Animal)
    like($inherit_xs, qr/class_apply_attributes.*isa\(Animal\)/s,
        'BOOT block contains class_apply_attributes with isa(Animal)');

    # isa step comes after class_setup_stash
    like($inherit_xs, qr/class_setup_stash.*class_apply_attributes/s,
        'class_apply_attributes comes after class_setup_stash');

    # isa attribute uses OP_CONST with literal string
    like($inherit_xs, qr/newSVpvs\("isa\(Animal\)"\)/,
        'isa attribute uses newSVpvs with literal "isa(Animal)"');

    # No our @ISA in output
    unlike($inherit_xs, qr/our\s+\@ISA/,
        'no our @ISA in XS output (inheritance via class_apply_attributes)');

    # isa applied before LEAVE (which triggers implicit seal)
    like($inherit_xs, qr/class_apply_attributes.*LEAVE/s,
        'class_apply_attributes comes before LEAVE (implicit seal)');
}

# Test native XSUB emission for methods
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
ok(defined $fallback_ir, 'parse class with methods produces IR');

SKIP: {
    skip 'no fallback IR', 7 unless defined $fallback_ir;

    my $fallback_target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Calculator');
    my $fallback_xs = $fallback_target->generate_with_cfg($fallback_ir, $fallback_sa, $fallback_sem_ctx);

    # multiply() emits as native XSUB using ObjectFIELDS for field access
    like($fallback_xs, qr/multiply\(self, x\)/,
        'multiply() emitted as native XSUB');
    like($fallback_xs, qr/ObjectFIELDS\(SvRV\(self\)\)\[\d+\]/,
        'multiply() uses ObjectFIELDS for field access');

    # check_type() emits as native XSUB using sv_derived_from_sv for isa
    like($fallback_xs, qr/check_type\(self, obj\)/,
        'check_type() emitted as native XSUB');
    like($fallback_xs, qr/sv_derived_from_sv/,
        'check_type() uses sv_derived_from_sv for isa operator');

    # call_coderef() emits as native XSUB using call_sv for coderef invocation
    like($fallback_xs, qr/call_coderef\(self, f\)/,
        'call_coderef() emitted as native XSUB');
    like($fallback_xs, qr/call_sv\(f,/,
        'call_coderef() uses call_sv for coderef invocation');

    # No eval_pv fallbacks needed for these methods
    unlike($fallback_xs, qr/eval_pv\("sub Calculator::(multiply|check_type|call_coderef)/,
        'no eval_pv fallback needed for any Calculator methods');
}

done_testing();
