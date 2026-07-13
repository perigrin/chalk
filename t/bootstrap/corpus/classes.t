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
# SECTION 1: Parse classes.md and verify the topic's named idioms are present.
#
# This runner asserts the STATIC inventory + shape of the corpus file. The
# authoritative behavior/shape/invariant gate is t/bootstrap/corpus/son-corpus-wide.t,
# which lowers each case's PERL SOURCE through B::SoN -> chalk -> lli. The old
# per-case run_case checks here lowered the hand-written IR BLOCK through the
# constructive builder -- a second, drifting lowering path that reported GAP on
# cases son-corpus-wide.t gates GREEN (void-method effects), and its hardcoded
# case counts went stale on every corpus addition (zhi 019f53a0). Retired here in
# favor of the single authoritative gate; the presence/node-line/guard checks
# below lower nothing and stay.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($CLASSES_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /class-simple/i   } @titles), 'case: class-simple present');
ok((grep { /field-basic/i    } @titles), 'case: field-basic present');
ok((grep { /field-attrs/i    } @titles), 'case: field-attrs present');
ok((grep { /method-simple/i  } @titles), 'case: method-simple present');
ok((grep { /method-call/i    } @titles), 'case: method-call present');
ok((grep { /class-isa/i      } @titles), 'case: class-isa present');
ok((grep { /adjust/i         } @titles), 'case: adjust present');

# ---------------------------------------------------------------------------
# SECTION 3: Every GREEN case's ir block declares L: GREEN (static parse).
# ---------------------------------------------------------------------------

subtest 'every GREEN-declared case parses its L: GREEN verdict' => sub {
    my @green = grep {
        Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($_->{ir} // '') eq 'GREEN'
    } @$cases;
    plan tests => scalar @green;
    for my $case (@green) {
        my $title = lc($case->{title});
        $title =~ s/^\s+|\s+$//g;
        my $decl = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($case->{ir} // '');
        is($decl, 'GREEN', "case '$title': declared L: GREEN");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Every GREEN ir block has %name = ... node lines (constructive graph).
# ---------------------------------------------------------------------------

subtest 'all GREEN ir blocks have node lines' => sub {
    my @green = grep {
        Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($_->{ir} // '') eq 'GREEN'
    } @$cases;
    plan tests => scalar @green;
    for my $case (@green) {
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
