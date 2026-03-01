# ABOUTME: Test that XS field access uses ObjectFIELDS for feature class objects.
# ABOUTME: Validates that hash-based access patterns (hv_fetch/HV*) are not used for self fields.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

# --- Test 1: _build_field_index_map strips all sigils ---
# Parse a class with scalar, hash, and array fields

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSFieldTest') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

use File::Temp qw(tempfile);
my ($fh, $filename) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class TestFields {
    field $name :param :reader;
    field $count = 0;
    field %cache;
    field @items;

    method get_count() {
        return $count;
    }

    method add_item($item) {
        push @items, $item;
        return $count;
    }

    method lookup($key) {
        return $cache{$key};
    }
}
PERL
close $fh;

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $filename) };
ok(defined $ir, 'test class parses to IR') or BAIL_OUT("Parse failed: $@");

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::Fields');
my $code = eval { $xs->generate_with_cfg($ir, $sa, $ctx) };
ok(defined $code, 'XS code generated') or BAIL_OUT("XS gen failed: $@");

# --- Test 2: field_map covers hash and array fields ---
# All field accesses should use ObjectFIELDS, not hv_fetch(hash, ...)
# Specifically: $name, $count, %cache, @items should all be ObjectFIELDS

my @field_hv_fetches;
while ($code =~ /hv_fetch\(hash,\s*"([^"]+)"/g) {
    push @field_hv_fetches, $1;
}

# Filter to only the known field names (without sigils)
my %earley_fields = map { $_ => 1 } qw(name count cache items);
my @field_fallbacks = grep { $earley_fields{$_} } @field_hv_fetches;

is(scalar @field_fallbacks, 0, 'no field accesses use hv_fetch fallback')
    or diag("Fields using hv_fetch instead of ObjectFIELDS: " . join(', ', @field_fallbacks));

# --- Test 3: ObjectFIELDS used for field access ---
my @obj_fields;
while ($code =~ /ObjectFIELDS\(SvRV\(self\)\)\[(\d+)\]/g) {
    push @obj_fields, $1;
}

ok(scalar @obj_fields > 0, 'ObjectFIELDS used for field access')
    or diag("No ObjectFIELDS found in generated XS");

# --- Test 4: no HV* hash = (HV*)SvRV(self) pattern ---
# Feature class objects are OBJECT reftype, not HASH.
# The hash = (HV*)SvRV(self) pattern will segfault.
unlike($code, qr/hash = \(HV\*\)SvRV\(self\)/,
    'no hash = (HV*)SvRV(self) in generated XS');

# --- Test 5: no HV *hash declaration ---
unlike($code, qr/HV \*hash;/,
    'no HV *hash variable declaration');

# --- Test 6: no SV **svp declaration (only needed for hv_fetch) ---
# svp is only needed as a temp for hv_fetch. If we have no hv_fetch
# for self fields, we might still need it for hashref subscript access.
# But it should not appear if there are no hv_fetch patterns at all.
my $has_any_hv_fetch = ($code =~ /hv_fetch\(hash,/);
if (!$has_any_hv_fetch) {
    unlike($code, qr/SV \*\*svp;/,
        'no SV **svp declaration when no hv_fetch(hash,...) used');
}

# --- Test 7: Earley.pm field coverage ---
# Parse the real Earley.pm and verify ALL fields use ObjectFIELDS
my ($eir, $esa, $ectx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
SKIP: {
    skip 'Earley.pm parse failed', 2 unless defined $eir;

    my $exs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::Earley');
    my $ecode = eval { $exs->generate_with_cfg($eir, $esa, $ectx) };
    ok(defined $ecode, 'Earley.pm XS generated');

    # Check that known Earley fields don't appear in hv_fetch(hash,...)
    my %earley_field_names = map { $_ => 1 }
        qw(grammar semiring rule_table core_index lr0_dfa
           waiting_for completed_at leo_items _leo_enabled
           _waiting_for_min _leo_origin_min _scan_cache regex_cache
           _gc_stats _gc_min_origin_at _gc_current_pos _gc_future_min);

    my @earley_fallbacks;
    while ($ecode =~ /hv_fetch\(hash,\s*"([^"]+)"/g) {
        push @earley_fallbacks, $1 if $earley_field_names{$1};
    }

    is(scalar @earley_fallbacks, 0,
        'Earley.pm: no field accesses use hv_fetch fallback')
        or diag("Earley fields using hv_fetch: " . join(', ', @earley_fallbacks));
}

# --- Test 8: ADJUST block emission for Earley.pm ---
# Earley.pm has an ADJUST block that builds rule_table, core_index, lr0_dfa.
# This must be emitted as eval_pv("ADJUST { ... }") inside the BOOT block
# BEFORE the LEAVE that seals the class.
SKIP: {
    skip 'Earley.pm parse failed', 3 unless defined $eir;

    my $exs2 = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::Earley2');
    my $ecode2 = eval { $exs2->generate_with_cfg($eir, $esa, $ectx) };
    ok(defined $ecode2, 'Earley.pm XS generated for ADJUST test');

    # The BOOT block should contain eval_pv with ADJUST
    like($ecode2, qr/eval_pv.*ADJUST/s,
        'BOOT block contains eval_pv with ADJUST keyword');

    # The ADJUST eval_pv should appear BEFORE the outer LEAVE
    # (which seals the class)
    my ($adjust_pos) = ($ecode2 =~ /(.*)eval_pv.*ADJUST/s);
    my ($leave_pos)  = ($ecode2 =~ /(.*)LEAVE;/s);
    if (defined $adjust_pos && defined $leave_pos) {
        ok(length($adjust_pos) < length($leave_pos),
            'ADJUST eval_pv appears before final LEAVE');
    } else {
        fail('ADJUST eval_pv appears before final LEAVE');
    }
}

done_testing();
