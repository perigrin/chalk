# ABOUTME: Tests FilterComposite dispatch unrolling in multi-class XS emission.
# ABOUTME: Verifies loop bodies use direct _impl_ calls instead of call_method.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSFilterUnroll') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

use File::Temp qw(tempfile);

# --- Simple semiring class: has is_zero, should_scan, multiply ---
my ($fh_sr, $file_sr) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_sr <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class SimpleSemiring {
    field $zero_val :param;

    method is_zero($value) {
        return $value;
    }

    method should_scan($item, $alt_idx, $pos, $text, $pred) {
        return $item;
    }

    method multiply($left, $right) {
        return $left;
    }
}
PERL
close $fh_sr;

# --- FilterComposite-like class: iterates over $semirings ---
my ($fh_fc, $file_fc) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_fc <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class FilterComposite {
    field $semirings :param :reader;

    method is_zero($value) {
        for my $i (0 .. $semirings->$#*) {
            return $value if $semirings->[$i]->is_zero($value->[$i]);
        }
        return $value;
    }

    method should_scan($item, $alt_idx, $pos, $text, $pred) {
        for my $i (0 .. $semirings->$#*) {
            my $component_item = $item;
            return $item unless $semirings->[$i]->should_scan(
                $component_item, $alt_idx, $pos, $text, $pred
            );
        }
        return $item;
    }
}
PERL
close $fh_fc;

my ($ir_sr, $sa_sr, $ctx_sr) = eval { parse_file_ir($gen, $file_sr) };
ok(defined $ir_sr, 'SimpleSemiring parses') or BAIL_OUT("Parse failed: $@");

my ($ir_fc, $sa_fc, $ctx_fc) = eval { parse_file_ir($gen, $file_fc) };
ok(defined $ir_fc, 'FilterComposite parses') or BAIL_OUT("Parse failed: $@");

# --- Register classes with component mapping ---
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg->register('SimpleSemiring', {
    ir => $ir_sr, sa => $sa_sr, ctx => $ctx_sr, uses => [],
});
$reg->register('FilterComposite', {
    ir => $ir_fc, sa => $sa_fc, ctx => $ctx_fc, uses => ['SimpleSemiring'],
    # composite_components maps field name to ordered list of component class names.
    # This tells the emitter that $semirings->[$i]->method() targets known classes.
    composite_components => {
        semirings => ['SimpleSemiring', 'SimpleSemiring'],
    },
});

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::FilterUnroll',
    class_registry => $reg,
);

my $code = eval { $xs->generate_multi_class([
    { class_name => 'SimpleSemiring', ir => $ir_sr, sa => $sa_sr, ctx => $ctx_sr },
    { class_name => 'FilterComposite', ir => $ir_fc, sa => $sa_fc, ctx => $ctx_fc },
]) };
ok(defined $code, 'multi-class generation succeeds')
    or BAIL_OUT("Multi-class gen failed: $@");

# Helper: extract the body of an _impl_ function from generated code
sub extract_impl_body($code_text, $impl_name) {
    # Match from function definition (with opening brace) to its closing brace
    # The \{ in the pattern ensures we skip forward declarations (which end with ;)
    my ($body) = $code_text =~ /(static\s+SV\s*\*\s*${impl_name}\(pTHX_[^;{]*\{.*?^})/ms;
    return $body;
}

# --- Test 1: is_zero body uses direct _impl_ call, not call_method ---
my $iz_body = extract_impl_body($code, '_impl_filtercomposite_is_zero');
ok(defined $iz_body, 'FilterComposite is_zero helper emitted')
    or diag "Full code:\n$code";

SKIP: {
    skip 'is_zero body not found', 2 unless defined $iz_body;

    like($iz_body, qr/_impl_simplesemiring_is_zero\(aTHX_/,
        'is_zero body calls _impl_simplesemiring_is_zero directly');
    unlike($iz_body, qr/call_method\("is_zero"/,
        'is_zero body has no call_method("is_zero")');
}

# --- Test 2: should_scan body uses direct _impl_ call, not call_method ---
my $ss_body = extract_impl_body($code, '_impl_filtercomposite_should_scan');
ok(defined $ss_body, 'FilterComposite should_scan helper emitted')
    or diag "Full code:\n$code";

SKIP: {
    skip 'should_scan body not found', 2 unless defined $ss_body;

    like($ss_body, qr/_impl_simplesemiring_should_scan\(aTHX_/,
        'should_scan body calls _impl_simplesemiring_should_scan directly');
    unlike($ss_body, qr/call_method\("should_scan"/,
        'should_scan body has no call_method("should_scan")');
}

# === Heterogeneous composite: two different component types ===

# --- SemiringA: has is_zero ---
my ($fh_a, $file_a) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_a <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class SemiringA {
    field $zero_val :param;

    method is_zero($value) {
        return $value;
    }
}
PERL
close $fh_a;

# --- SemiringB: has is_zero ---
my ($fh_b, $file_b) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_b <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class SemiringB {
    field $zero_val :param;

    method is_zero($value) {
        return $value;
    }
}
PERL
close $fh_b;

# --- HeteroComposite: iterates over two different semiring types ---
my ($fh_hc, $file_hc) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh_hc <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class HeteroComposite {
    field $semirings :param :reader;

    method is_zero($value) {
        for my $i (0 .. $semirings->$#*) {
            return $value if $semirings->[$i]->is_zero($value->[$i]);
        }
        return $value;
    }
}
PERL
close $fh_hc;

my ($ir_a2, $sa_a2, $ctx_a2) = eval { parse_file_ir($gen, $file_a) };
ok(defined $ir_a2, 'SemiringA parses') or BAIL_OUT("Parse failed: $@");

my ($ir_b2, $sa_b2, $ctx_b2) = eval { parse_file_ir($gen, $file_b) };
ok(defined $ir_b2, 'SemiringB parses') or BAIL_OUT("Parse failed: $@");

my ($ir_hc, $sa_hc, $ctx_hc) = eval { parse_file_ir($gen, $file_hc) };
ok(defined $ir_hc, 'HeteroComposite parses') or BAIL_OUT("Parse failed: $@");

my $reg2 = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg2->register('SemiringA', { ir => $ir_a2, sa => $sa_a2, ctx => $ctx_a2, uses => [] });
$reg2->register('SemiringB', { ir => $ir_b2, sa => $sa_b2, ctx => $ctx_b2, uses => [] });
$reg2->register('HeteroComposite', {
    ir => $ir_hc, sa => $sa_hc, ctx => $ctx_hc,
    uses => ['SemiringA', 'SemiringB'],
    composite_components => {
        semirings => ['SemiringA', 'SemiringB'],
    },
});

my $xs2 = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::HeteroUnroll',
    class_registry => $reg2,
);

my $code2 = eval { $xs2->generate_multi_class([
    { class_name => 'SemiringA', ir => $ir_a2, sa => $sa_a2, ctx => $ctx_a2 },
    { class_name => 'SemiringB', ir => $ir_b2, sa => $sa_b2, ctx => $ctx_b2 },
    { class_name => 'HeteroComposite', ir => $ir_hc, sa => $sa_hc, ctx => $ctx_hc },
]) };
ok(defined $code2, 'heterogeneous multi-class generation succeeds')
    or BAIL_OUT("Hetero multi-class gen failed: $@");

# --- Test: heterogeneous is_zero should use BOTH component _impl_ calls ---
my $hc_iz_body = extract_impl_body($code2, '_impl_heterocomposite_is_zero');
ok(defined $hc_iz_body, 'HeteroComposite is_zero helper emitted');

SKIP: {
    skip 'HeteroComposite is_zero body not found', 3 unless defined $hc_iz_body;

    like($hc_iz_body, qr/_impl_semiringa_is_zero\(aTHX_/,
        'hetero is_zero calls _impl_semiringa_is_zero');
    like($hc_iz_body, qr/_impl_semiringb_is_zero\(aTHX_/,
        'hetero is_zero calls _impl_semiringb_is_zero');
    unlike($hc_iz_body, qr/call_method\("is_zero"/,
        'hetero is_zero has no call_method("is_zero")');
}

done_testing();
