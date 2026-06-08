# ABOUTME: Runner for the classes mdtest corpus topic (constructive format).
# ABOUTME: Exercises 7 feature-class MOP idioms; flipped to GREEN as G5 lowering is implemented.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;

my $CLASSES_MD = 't/corpus/mdtest/classes.md';

unless (-f $CLASSES_MD) {
    plan skip_all => "classes.md not found at $CLASSES_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse classes.md and verify case inventory
#
# All 7 class idioms must be present.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($CLASSES_MD);
is(scalar(@$cases), 7, 'classes.md has 7 cases');

my @titles = map { $_->{title} } @$cases;
ok((grep { /class-simple/i   } @titles), 'case: class-simple present');
ok((grep { /field-basic/i    } @titles), 'case: field-basic present');
ok((grep { /field-attrs/i    } @titles), 'case: field-attrs present');
ok((grep { /method-simple/i  } @titles), 'case: method-simple present');
ok((grep { /method-call/i    } @titles), 'case: method-call present');
ok((grep { /class-isa/i      } @titles), 'case: class-isa present');
ok((grep { /adjust/i         } @titles), 'case: adjust present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 7 cases end-to-end
#
# GREEN cases: behavior, ir-shape, and L-verdict must all PASS.
# GAP cases: behavior must PASS, ir-shape must not FAIL, L-verdict is GAP.
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        # Behavior check: perl oracle must agree with declared return
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape check: pure-GAP blocks trivially pass (no graph to validate)
        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape fail: " . join('; ', @{ $result->{fail_reasons} }));

        # L-verdict check: declared verdict must match actual
        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        # Overall
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));
    };
}

# ---------------------------------------------------------------------------
# SECTION 3: Verify all 7 cases declare L: GREEN
#
# G5 complete: all 7 class idioms are lowerable without libperl.
# ---------------------------------------------------------------------------

my @all_case_names = qw(class-simple method-simple field-basic field-attrs method-call class-isa adjust);

subtest 'all 7 cases declare L: GREEN' => sub {
    plan tests => 7;
    for my $case (@$cases) {
        my $title = lc($case->{title});
        $title =~ s/^\s+|\s+$//g;
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        is($decl, 'GREEN', "case '$title': declared L: GREEN");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Verify all GREEN ir blocks have node lines
#
# A GREEN ir block must have %name = ... node lines (constructive graph).
# ---------------------------------------------------------------------------

subtest 'all GREEN ir blocks have node lines' => sub {
    plan tests => 7;
    for my $case (@$cases) {
        my $title = lc($case->{title});
        $title =~ s/^\s+|\s+$//g;
        my $ir_text = $case->{ir} // '';
        my $has_node_lines = ($ir_text =~ /^%\w+\s*=/m) ? 1 : 0;
        ok($has_node_lines, "case '$title': GREEN ir block has node lines (constructive graph)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — a class idiom claiming L: GREEN must FAIL
# if the block is pure-GAP (no constructive graph).
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for class idiom FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN class-simple case

```perl
# source
use feature 'class';
no warnings 'experimental::class';
class Foo { }
my $f = Foo->new;
ref($f)
```

```behavior
return: Foo
context: scalar
```

```ir
L: GREEN
```
END_MD

    use File::Temp qw(tempfile);
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $fake_green_md;
    close $fh;

    my $fake_cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $fake_case  = $fake_cases->[0];
    my $result     = Chalk::CodeGen::Harness::MdtestCorpus->run_case($fake_case, {});

    is($result->{l_verdict}{verdict}, 'FAIL',
        'pure-GAP block (no nodes) claiming L: GREEN is FAIL');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(scalar(@{ $result->{fail_reasons} }) > 0, 'at least one fail reason recorded');
    like($result->{fail_reasons}[0] // '', qr/L verdict|GAP|GREEN/i,
        'fail reason mentions L verdict, GAP, or GREEN');
};

done_testing;
