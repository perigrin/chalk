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

done_testing();
