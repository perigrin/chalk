# ABOUTME: Cross-load validation: load perl5-son B::SoN JSON output into Chalk IR.
# ABOUTME: Proves the two projects produce compatible JSON for the node types both support.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# Chalk::IR::Serialize::JSON exports from_json, but JSON::PP also exports a
# from_json() function. Import via explicit package name to avoid the conflict.
use Chalk::IR::Serialize::JSON ();

my $perl    = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $son_lib = "$ENV{HOME}/dev/perl5-son/lib";

unless (-d $son_lib) {
    plan skip_all => "perl5-son not found at $son_lib";
}

unless (-f "$son_lib/B/SoN.pm") {
    plan skip_all => "B::SoN not found at $son_lib/B/SoN.pm";
}

# Helper: invoke B::SoN,json on a snippet and return the raw JSON string.
# The snippet must be a valid Perl expression that compiles under perl 5.42.0.
# Returns undef if B::SoN produces no usable output.
sub _run_son_json {
    my ($code) = @_;
    my $json = `$perl -I$son_lib -MO=SoN,json -e '$code' 2>/dev/null`;
    return undef unless defined $json && length($json) > 10;
    return $json;
}

# Helper: filter a full B::SoN JSON blob to contain only named methods, then
# deserialize via Chalk::IR::Serialize::JSON::from_json.
# Returns the Chalk graph hashref, or undef on any error.
#
# Filtering is necessary because B::SoN serializes every loaded module.
# Some of those modules contain node types (e.g. Stringify) not yet
# supported by Chalk's NodeFactory. Extracting just the named methods
# lets us validate schema compatibility for the representable subset.
sub _load_named_methods {
    my ($json, @names) = @_;
    require JSON::PP;
    my $data = eval { JSON::PP->new->decode($json) };
    return undef if $@;

    my %filtered_methods;
    for my $name (@names) {
        next unless exists $data->{methods}{$name};
        $filtered_methods{$name} = $data->{methods}{$name};
    }
    return undef unless %filtered_methods;

    my $filtered = {
        version => $data->{version} // 1,
        source  => undef,
        methods => \%filtered_methods,
    };

    my $filtered_json = JSON::PP->new->canonical->pretty->encode($filtered);
    my $result = eval { Chalk::IR::Serialize::JSON::from_json($filtered_json) };
    return undef if $@;
    return $result;
}

# =============================================================================
# Test 1: Simple arithmetic sub — foo { my $x = 42; $x + 1 }
# Verifies: Start, Return, Add, and Constant nodes load correctly.
# Verifies: Constant with value "42" and const_type "integer" survives.
# =============================================================================

{
    my $json = _run_son_json('sub foo { my $x = 42; $x + 1 }');
    ok(defined $json, 'Test 1: B::SoN produced JSON for arithmetic sub');

  SKIP: {
        skip 'no B::SoN JSON produced', 5 unless defined $json;

        my $loaded = _load_named_methods($json, 'main::foo');
        ok(defined $loaded, 'Test 1: from_json loaded main::foo without error');
        ok(exists $loaded->{'main::foo'}, 'Test 1: main::foo exists in loaded graphs');

        my $g    = $loaded->{'main::foo'};
        my @ops  = map { $_->operation() } $g->nodes()->@*;
        my %seen = map { $_ => 1 } @ops;

        ok($seen{Start},    'Test 1: Start node present');
        ok($seen{Return},   'Test 1: Return node present');
        ok($seen{Add},      'Test 1: Add node present');

        my ($const42) = grep {
            $_->operation() eq 'Constant'
            && defined $_->value()
            && $_->value() eq '42'
        } $g->nodes()->@*;

        ok(defined $const42, 'Test 1: Constant node with value 42 present');
        is($const42->const_type(), 'integer',
            'Test 1: Constant value=42 has const_type integer');
    }
}

# =============================================================================
# Test 2: Sub with string constant concatenation (constant-folded by compiler)
# The Perl compiler folds "hello" . " world" to a single string constant.
# This validates that Chalk loads a Constant node with const_type "string".
# =============================================================================

{
    # B::SoN silently skips subs it cannot translate (e.g. those with variable
    # concat involving pad-allocated strings).  Using literal constants lets the
    # compiler fold them, producing a simple Constant+Return graph that B::SoN
    # CAN translate.
    my $json = _run_son_json('sub bar { "hello" . " world" }');
    ok(defined $json, 'Test 2: B::SoN produced JSON for constant concat sub');

  SKIP: {
        skip 'no B::SoN JSON produced', 3 unless defined $json;

        require JSON::PP;
        my $data = eval { JSON::PP->new->decode($json) };
        my $bar_exists = defined $data && exists $data->{methods}{'main::bar'};

        ok($bar_exists, 'Test 2: main::bar found in B::SoN JSON');

      SKIP: {
            skip 'main::bar not in B::SoN output', 2 unless $bar_exists;

            my $loaded = _load_named_methods($json, 'main::bar');
            ok(defined $loaded, 'Test 2: from_json loaded main::bar without error');

            my $g = $loaded->{'main::bar'};
            my ($const) = grep {
                $_->operation() eq 'Constant'
                && defined $_->const_type()
                && $_->const_type() eq 'string'
            } $g->nodes()->@*;

            ok(defined $const, 'Test 2: Constant node with const_type "string" present');
        }
    }
}

# =============================================================================
# Test 3: Sub with conditional — baz { my $x = 1; $x ? "yes" : "no" }
# Verifies: TernaryExpr node loads correctly from B::SoN JSON.
# =============================================================================

{
    my $json = _run_son_json('sub baz { my $x = 1; $x ? "yes" : "no" }');
    ok(defined $json, 'Test 3: B::SoN produced JSON for ternary sub');

  SKIP: {
        skip 'no B::SoN JSON produced', 3 unless defined $json;

        my $loaded = _load_named_methods($json, 'main::baz');
        ok(defined $loaded, 'Test 3: from_json loaded main::baz without error');
        ok(exists $loaded->{'main::baz'}, 'Test 3: main::baz exists in loaded graphs');

        my $g    = $loaded->{'main::baz'};
        my %seen = map { $_->operation() => 1 } $g->nodes()->@*;

        ok($seen{TernaryExpr}, 'Test 3: TernaryExpr node present');
    }
}

# =============================================================================
# Test 4: Sub with die — boom { die "error" }
# Verifies: Unwind CFG node loads correctly from B::SoN JSON.
# =============================================================================

{
    my $json = _run_son_json('sub boom { die "error" }');
    ok(defined $json, 'Test 4: B::SoN produced JSON for die sub');

  SKIP: {
        skip 'no B::SoN JSON produced', 3 unless defined $json;

        my $loaded = _load_named_methods($json, 'main::boom');
        ok(defined $loaded, 'Test 4: from_json loaded main::boom without error');
        ok(exists $loaded->{'main::boom'}, 'Test 4: main::boom exists in loaded graphs');

        my $g    = $loaded->{'main::boom'};
        my %seen = map { $_->operation() => 1 } $g->nodes()->@*;

        ok($seen{Unwind}, 'Test 4: Unwind node present');
    }
}

# =============================================================================
# Test 5: Sub with reference — make_ref { my $x = 1; \$x }
# Verifies: Ref node loads correctly from B::SoN JSON.
# =============================================================================

{
    my $json = _run_son_json('sub make_ref { my $x = 1; \$x }');
    ok(defined $json, 'Test 5: B::SoN produced JSON for reference sub');

  SKIP: {
        skip 'no B::SoN JSON produced', 3 unless defined $json;

        my $loaded = _load_named_methods($json, 'main::make_ref');
        ok(defined $loaded, 'Test 5: from_json loaded main::make_ref without error');
        ok(exists $loaded->{'main::make_ref'},
            'Test 5: main::make_ref exists in loaded graphs');

        my $g    = $loaded->{'main::make_ref'};
        my %seen = map { $_->operation() => 1 } $g->nodes()->@*;

        ok($seen{Ref}, 'Test 5: Ref node present');
    }
}

# =============================================================================
# Test 6: Schema incompatibility report
# Documents node types that appear in B::SoN output but are not supported
# by Chalk::IR::NodeFactory, verifying no regressions as coverage expands.
# =============================================================================

{
    # Chalk's NodeFactory supports these data node types.
    my %chalk_data_ops = map { $_ => 1 } qw(
        Constant Phi
        Add Subtract Multiply Divide Modulo Power Concat
        NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
        StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
        And Or BitAnd BitOr BitXor LeftShift RightShift
        Assign Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp
        Not Negate Complement Defined UnaryPlus Ref
        PadAccess FieldAccess StashAccess Subscript
        Call HashRef ArrayRef Interpolate AnonSub
        RegexMatch RegexSubst TryCatch
        PostfixDeref CompoundAssign BacktickExpr Stringify VarDecl
        TernaryExpr StructRef StructFieldAccess
    );

    my %chalk_cfg_ops = map { $_ => 1 } qw(
        Start Return Unwind If Proj Region Loop
    );

    my $json = _run_son_json('sub foo { my $x = 42; $x + 1 }');

  SKIP: {
        skip 'no B::SoN JSON for schema check', 1 unless defined $json;

        require JSON::PP;
        my $data = JSON::PP->new->decode($json);

        my %son_ops;
        for my $method (values $data->{methods}->%*) {
            for my $node ($method->{nodes}->@*) {
                $son_ops{ $node->{op} }++;
            }
        }

        my @unsupported = sort grep {
            !exists $chalk_data_ops{$_} && !exists $chalk_cfg_ops{$_}
        } keys %son_ops;

        # Document the known incompatibilities. If this list shrinks in future,
        # the test will still pass — it is informational, not a hard failure.
        note "Node types in B::SoN output not yet in Chalk::IR::NodeFactory:";
        note "  $_" for @unsupported;

        # All node types in B::SoN output should now be supported by Chalk.
        ok(!@unsupported,
            'Test 6: all B::SoN node types supported by Chalk NodeFactory')
            or diag "Unsupported ops: @unsupported";
    }
}

done_testing;
