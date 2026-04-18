# ABOUTME: Per-file SoN IR comparison between Chalk and perl5-son (B::SoN).
# ABOUTME: Runs both pipelines on each .pm file, diffs JSON, reports divergences.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP ();

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------

my $perl     = $ENV{CHALK_PERL} // $^X;
my $son_lib  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $chalk_script = 'script/chalk-emit-son-json';

# Verify perl5-son is available
unless (-d $son_lib && -f "$son_lib/B/SoN.pm") {
    plan skip_all => "perl5-son not found at $son_lib (set PERL5_SON_LIB)";
}

unless (-f $chalk_script) {
    plan skip_all => "chalk-emit-son-json not found";
}

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

sub run_bson ($file, $package) {
    my $cmd = "$perl -Ilib -I$son_lib -MO=SoN,json,package=$package $file 2>/dev/null";
    my $output = `$cmd`;
    return ($? >> 8, $output);
}

sub run_chalk ($file) {
    my $cmd = "$perl -Ilib -It/bootstrap/lib $chalk_script $file 2>/dev/null";
    my $output = `$cmd`;
    return ($? >> 8, $output);
}

sub decode_json ($str) {
    return eval { JSON::PP->new->decode($str) };
}

sub method_names ($json_str) {
    my $data = decode_json($json_str);
    return () unless defined $data && ref $data->{methods} eq 'HASH';
    return sort keys $data->{methods}->%*;
}

# Compare op-type multisets (unordered) between two method graphs.
# Returns a hashref with match details.
sub compare_method_ops ($bson_data, $chalk_data, $method_name) {
    my $bson_m  = $bson_data->{methods}{$method_name};
    my $chalk_m = $chalk_data->{methods}{$method_name};

    return { status => 'missing_bson' }  unless defined $bson_m;
    return { status => 'missing_chalk' } unless defined $chalk_m;

    my @bson_ops  = map { $_->{op} } $bson_m->{nodes}->@*;
    my @chalk_ops = map { $_->{op} } $chalk_m->{nodes}->@*;

    # Exact sequence match
    my $seq_match = (join(',', @bson_ops) eq join(',', @chalk_ops));

    # Op-type multiset comparison (order-independent)
    my %bson_bag;
    $bson_bag{$_}++ for @bson_ops;
    my %chalk_bag;
    $chalk_bag{$_}++ for @chalk_ops;

    my %all_ops;
    @all_ops{ keys %bson_bag, keys %chalk_bag } = ();
    my @only_bson  = grep { ($bson_bag{$_} // 0) > ($chalk_bag{$_} // 0) } sort keys %all_ops;
    my @only_chalk = grep { ($chalk_bag{$_} // 0) > ($bson_bag{$_} // 0) } sort keys %all_ops;

    return {
        status      => $seq_match ? 'exact_match' : 'diverged',
        bson_count  => scalar @bson_ops,
        chalk_count => scalar @chalk_ops,
        bson_ops    => \@bson_ops,
        chalk_ops   => \@chalk_ops,
        only_bson   => \@only_bson,
        only_chalk  => \@only_chalk,
    };
}

# -----------------------------------------------------------------------
# Test files: (file, package) pairs where both Chalk and B::SoN produce output
# -----------------------------------------------------------------------

my @test_cases = (
    # Top-level IR/*.pm files (partial parse coverage — several still fail Chalk parse)
    ['lib/Chalk/IR/UseInfo.pm',    'Chalk::IR::UseInfo'],
    ['lib/Chalk/IR/ClassInfo.pm',  'Chalk::IR::ClassInfo'],
    ['lib/Chalk/IR/MethodInfo.pm', 'Chalk::IR::MethodInfo'],
    ['lib/Chalk/IR/SubInfo.pm',    'Chalk::IR::SubInfo'],
    ['lib/Chalk/IR/Program.pm',    'Chalk::IR::Program'],
    ['lib/Chalk/IR/Node.pm',       'Chalk::IR::Node'],
    ['lib/Chalk/IR/Graph.pm',      'Chalk::IR::Graph'],

    # IR/Node/*.pm files — all parse with both Chalk and B::SoN.
    # Simple nodes: only have operation() / op_str() methods.
    ['lib/Chalk/IR/Node/Add.pm',            'Chalk::IR::Node::Add'],
    ['lib/Chalk/IR/Node/And.pm',            'Chalk::IR::Node::And'],
    ['lib/Chalk/IR/Node/Assign.pm',         'Chalk::IR::Node::Assign'],
    ['lib/Chalk/IR/Node/BitAnd.pm',         'Chalk::IR::Node::BitAnd'],
    ['lib/Chalk/IR/Node/BitOr.pm',          'Chalk::IR::Node::BitOr'],
    ['lib/Chalk/IR/Node/BitXor.pm',         'Chalk::IR::Node::BitXor'],
    ['lib/Chalk/IR/Node/Concat.pm',         'Chalk::IR::Node::Concat'],
    ['lib/Chalk/IR/Node/Divide.pm',         'Chalk::IR::Node::Divide'],
    ['lib/Chalk/IR/Node/If.pm',             'Chalk::IR::Node::If'],
    ['lib/Chalk/IR/Node/LeftShift.pm',      'Chalk::IR::Node::LeftShift'],
    ['lib/Chalk/IR/Node/Modulo.pm',         'Chalk::IR::Node::Modulo'],
    ['lib/Chalk/IR/Node/Multiply.pm',       'Chalk::IR::Node::Multiply'],
    ['lib/Chalk/IR/Node/NumCmp.pm',         'Chalk::IR::Node::NumCmp'],
    ['lib/Chalk/IR/Node/NumEq.pm',          'Chalk::IR::Node::NumEq'],
    ['lib/Chalk/IR/Node/NumGe.pm',          'Chalk::IR::Node::NumGe'],
    ['lib/Chalk/IR/Node/NumGt.pm',          'Chalk::IR::Node::NumGt'],
    ['lib/Chalk/IR/Node/NumLe.pm',          'Chalk::IR::Node::NumLe'],
    ['lib/Chalk/IR/Node/NumLt.pm',          'Chalk::IR::Node::NumLt'],
    ['lib/Chalk/IR/Node/NumNe.pm',          'Chalk::IR::Node::NumNe'],
    ['lib/Chalk/IR/Node/Or.pm',             'Chalk::IR::Node::Or'],
    ['lib/Chalk/IR/Node/Power.pm',          'Chalk::IR::Node::Power'],
    ['lib/Chalk/IR/Node/Range.pm',          'Chalk::IR::Node::Range'],
    ['lib/Chalk/IR/Node/Ref.pm',            'Chalk::IR::Node::Ref'],
    ['lib/Chalk/IR/Node/RegexMatch.pm',     'Chalk::IR::Node::RegexMatch'],
    ['lib/Chalk/IR/Node/Repeat.pm',         'Chalk::IR::Node::Repeat'],
    ['lib/Chalk/IR/Node/Return.pm',         'Chalk::IR::Node::Return'],
    ['lib/Chalk/IR/Node/RightShift.pm',     'Chalk::IR::Node::RightShift'],
    ['lib/Chalk/IR/Node/Start.pm',          'Chalk::IR::Node::Start'],
    ['lib/Chalk/IR/Node/StrCmp.pm',         'Chalk::IR::Node::StrCmp'],
    ['lib/Chalk/IR/Node/StrEq.pm',          'Chalk::IR::Node::StrEq'],
    ['lib/Chalk/IR/Node/StrGe.pm',          'Chalk::IR::Node::StrGe'],
    ['lib/Chalk/IR/Node/StrGt.pm',          'Chalk::IR::Node::StrGt'],
    ['lib/Chalk/IR/Node/StrLe.pm',          'Chalk::IR::Node::StrLe'],
    ['lib/Chalk/IR/Node/StrLt.pm',          'Chalk::IR::Node::StrLt'],
    ['lib/Chalk/IR/Node/StrNe.pm',          'Chalk::IR::Node::StrNe'],
    ['lib/Chalk/IR/Node/Subtract.pm',       'Chalk::IR::Node::Subtract'],
    ['lib/Chalk/IR/Node/Xor.pm',            'Chalk::IR::Node::Xor'],
    # Nodes with extra methods or more complex bodies
    ['lib/Chalk/IR/Node/BinOp.pm',          'Chalk::IR::Node::BinOp'],
    ['lib/Chalk/IR/Node/UnaryOp.pm',        'Chalk::IR::Node::UnaryOp'],
    ['lib/Chalk/IR/Node/Constant.pm',       'Chalk::IR::Node::Constant'],
    ['lib/Chalk/IR/Node/Call.pm',           'Chalk::IR::Node::Call'],
    ['lib/Chalk/IR/Node/FieldAccess.pm',    'Chalk::IR::Node::FieldAccess'],
    ['lib/Chalk/IR/Node/PadAccess.pm',      'Chalk::IR::Node::PadAccess'],
    ['lib/Chalk/IR/Node/StashAccess.pm',    'Chalk::IR::Node::StashAccess'],
    ['lib/Chalk/IR/Node/Loop.pm',           'Chalk::IR::Node::Loop'],
    ['lib/Chalk/IR/Node/Phi.pm',            'Chalk::IR::Node::Phi'],
    ['lib/Chalk/IR/Node/AnonSub.pm',        'Chalk::IR::Node::AnonSub'],
    ['lib/Chalk/IR/Node/Regex.pm',          'Chalk::IR::Node::Regex'],
    ['lib/Chalk/IR/Node/RegexSubst.pm',     'Chalk::IR::Node::RegexSubst'],
    ['lib/Chalk/IR/Node/Proj.pm',           'Chalk::IR::Node::Proj'],
    ['lib/Chalk/IR/Node/VarDecl.pm',        'Chalk::IR::Node::VarDecl'],
    ['lib/Chalk/IR/Node/PostfixDeref.pm',   'Chalk::IR::Node::PostfixDeref'],
    ['lib/Chalk/IR/Node/Subscript.pm',      'Chalk::IR::Node::Subscript'],
    ['lib/Chalk/IR/Node/TernaryExpr.pm',    'Chalk::IR::Node::TernaryExpr'],
    ['lib/Chalk/IR/Node/CompoundAssign.pm', 'Chalk::IR::Node::CompoundAssign'],
    ['lib/Chalk/IR/Node/Interpolate.pm',    'Chalk::IR::Node::Interpolate'],
    ['lib/Chalk/IR/Node/HashRef.pm',        'Chalk::IR::Node::HashRef'],
    ['lib/Chalk/IR/Node/ArrayRef.pm',       'Chalk::IR::Node::ArrayRef'],
    ['lib/Chalk/IR/Node/Aggregate.pm',      'Chalk::IR::Node::Aggregate'],
    ['lib/Chalk/IR/Node/Defined.pm',        'Chalk::IR::Node::Defined'],
    ['lib/Chalk/IR/Node/DefinedOr.pm',      'Chalk::IR::Node::DefinedOr'],
    ['lib/Chalk/IR/Node/Match.pm',          'Chalk::IR::Node::Match'],
    ['lib/Chalk/IR/Node/NotMatch.pm',       'Chalk::IR::Node::NotMatch'],
    ['lib/Chalk/IR/Node/Not.pm',            'Chalk::IR::Node::Not'],
    ['lib/Chalk/IR/Node/Negate.pm',         'Chalk::IR::Node::Negate'],
    ['lib/Chalk/IR/Node/Complement.pm',     'Chalk::IR::Node::Complement'],
    ['lib/Chalk/IR/Node/UnaryPlus.pm',      'Chalk::IR::Node::UnaryPlus'],
    ['lib/Chalk/IR/Node/IsaOp.pm',          'Chalk::IR::Node::IsaOp'],
    ['lib/Chalk/IR/Node/Stringify.pm',      'Chalk::IR::Node::Stringify'],
    ['lib/Chalk/IR/Node/Region.pm',         'Chalk::IR::Node::Region'],
    ['lib/Chalk/IR/Node/TryCatch.pm',       'Chalk::IR::Node::TryCatch'],
    ['lib/Chalk/IR/Node/Unwind.pm',         'Chalk::IR::Node::Unwind'],
    ['lib/Chalk/IR/Node/BacktickExpr.pm',   'Chalk::IR::Node::BacktickExpr'],
    ['lib/Chalk/IR/Node/Access.pm',         'Chalk::IR::Node::Access'],
    ['lib/Chalk/IR/Node/StructFieldAccess.pm', 'Chalk::IR::Node::StructFieldAccess'],
    ['lib/Chalk/IR/Node/StructRef.pm',      'Chalk::IR::Node::StructRef'],
    ['lib/Chalk/IR/Node/Length.pm',         'Chalk::IR::Node::Length'],
    ['lib/Chalk/IR/Node/Slice.pm',          'Chalk::IR::Node::Slice'],
    ['lib/Chalk/IR/Node/Yada.pm',           'Chalk::IR::Node::Yada'],
);

# -----------------------------------------------------------------------
# Aggregation counters
# -----------------------------------------------------------------------

my %totals = (
    files_tested    => 0,
    methods_common  => 0,
    exact_matches   => 0,
    divergences     => 0,
    bson_only       => 0,
    chalk_only      => 0,
);

# Divergence categories: op types that appear exclusively in one pipeline
my %bson_exclusive_ops;
my %chalk_exclusive_ops;

# -----------------------------------------------------------------------
# Run comparisons
# -----------------------------------------------------------------------

for my $tc (@test_cases) {
    my ($file, $pkg) = $tc->@*;

    subtest "$file" => sub {
        my ($bson_exit, $bson_json) = run_bson($file, $pkg);
        my ($chalk_exit, $chalk_json) = run_chalk($file);

        is($bson_exit, 0, "B::SoN exits 0");

        TODO: {
            local $TODO = "not all files parse cleanly yet" if $chalk_exit != 0;
            is($chalk_exit, 0, "Chalk exits 0");
        }

        return if $bson_exit != 0 || $chalk_exit != 0;

        my $bson_data  = decode_json($bson_json);
        my $chalk_data = decode_json($chalk_json);

        ok(defined $bson_data,  'B::SoN valid JSON');
        ok(defined $chalk_data, 'Chalk valid JSON');

        return unless defined $bson_data && defined $chalk_data;

        # Method sets
        my @bson_methods  = method_names($bson_json);
        my @chalk_methods = method_names($chalk_json);
        my %bson_set  = map { $_ => 1 } @bson_methods;
        my %chalk_set = map { $_ => 1 } @chalk_methods;
        my @common     = grep { $bson_set{$_} } @chalk_methods;
        my @bson_only  = grep { !$chalk_set{$_} } @bson_methods;
        my @chalk_only = grep { !$bson_set{$_} } @chalk_methods;

        $totals{files_tested}++;
        $totals{bson_only}  += scalar @bson_only;
        $totals{chalk_only} += scalar @chalk_only;

        diag("common=" . scalar @common
           . " bson_only=" . scalar @bson_only
           . " chalk_only=" . scalar @chalk_only)
            if @common || @bson_only || @chalk_only;

        # Compare common methods
        for my $method (@common) {
            $totals{methods_common}++;
            my $r = compare_method_ops($bson_data, $chalk_data, $method);

            if ($r->{status} eq 'exact_match') {
                $totals{exact_matches}++;
                pass("$method: exact match ($r->{bson_count} nodes)");
            }
            else {
                $totals{divergences}++;
                $bson_exclusive_ops{$_}++  for $r->{only_bson}->@*;
                $chalk_exclusive_ops{$_}++ for $r->{only_chalk}->@*;

                TODO: {
                    local $TODO = "IR divergences expected";
                    fail("$method: diverged (B::SoN=$r->{bson_count} Chalk=$r->{chalk_count})");
                    if ($r->{only_bson}->@*) {
                        diag("  B::SoN extra ops: " . join(', ', $r->{only_bson}->@*));
                    }
                    if ($r->{only_chalk}->@*) {
                        diag("  Chalk extra ops: " . join(', ', $r->{only_chalk}->@*));
                    }
                }
            }
        }
    };
}

# -----------------------------------------------------------------------
# Summary report
# -----------------------------------------------------------------------

diag("");
diag("=== SoN Comparison Summary ===");
diag("Files tested:    $totals{files_tested}");
diag("Common methods:  $totals{methods_common}");
diag("Exact matches:   $totals{exact_matches}");
diag("Divergences:     $totals{divergences}");
diag("B::SoN only:     $totals{bson_only} methods");
diag("Chalk only:      $totals{chalk_only} methods");

if (%bson_exclusive_ops) {
    diag("");
    diag("Ops seen only in B::SoN (not Chalk):");
    for my $op (sort { $bson_exclusive_ops{$b} <=> $bson_exclusive_ops{$a} } keys %bson_exclusive_ops) {
        diag("  $op ($bson_exclusive_ops{$op}x)");
    }
}

if (%chalk_exclusive_ops) {
    diag("");
    diag("Ops seen only in Chalk (not B::SoN):");
    for my $op (sort { $chalk_exclusive_ops{$b} <=> $chalk_exclusive_ops{$a} } keys %chalk_exclusive_ops) {
        diag("  $op ($chalk_exclusive_ops{$op}x)");
    }
}

done_testing();
