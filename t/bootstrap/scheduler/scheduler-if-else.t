# ABOUTME: Tests EagerPinning scheduler structured expansion for if/else.
# ABOUTME: Phase 4a — If becomes block_open / [else] / block_close pairs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Scheduler::EagerPinning;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Scalar::Util qw(refaddr);

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SchedulerIfElseTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::SchedulerIfElseTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();

sub _parse_method($source) {
    $semiring->reset_cache();
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r = $parser->parse_value($source);
    return undef unless defined $r && !$r->is_zero();
    return undef unless defined $mop;
    for my $cls ($mop->classes()) {
        for my $m ($cls->methods) { return $m; }
    }
    return undef;
}

sub _kinds($sched) { return map { $_->kind } $sched->items->@*; }
sub _forms($sched) { return map { $_->form // '' } $sched->items->@*; }

# --- Test 1: if/else with both arms ---
{
    my $m = _parse_method(
        'class C { method m { my $x = 0; if ($x) { $x = 1; } else { $x = 2; } return $x; } }'
    );
    ok(defined $m, 'if/else method parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'if/else schedule is balanced');

    my @kinds = _kinds($sched);
    my @forms = _forms($sched);

    # Expect: stmt(VarDecl), block_open(if), stmt(Assign), else, stmt(Assign),
    #         block_close(if), stmt(Return).
    my $idx_open  = (grep { $kinds[$_] eq 'block_open' }  0..$#kinds)[0];
    my $idx_else  = (grep { $kinds[$_] eq 'else' }        0..$#kinds)[0];
    my $idx_close = (grep { $kinds[$_] eq 'block_close' } 0..$#kinds)[0];

    ok(defined $idx_open,  'has block_open');
    ok(defined $idx_else,  'has else');
    ok(defined $idx_close, 'has block_close');
    is($forms[$idx_open],  'if', 'block_open form is if');
    is($forms[$idx_close], 'if', 'block_close form is if');
    cmp_ok($idx_open, '<', $idx_else,  'block_open before else');
    cmp_ok($idx_else, '<', $idx_close, 'else before block_close');
}

# --- Test 2: if with no else ---
{
    my $m = _parse_method(
        'class C { method m { my $x = 0; if ($x) { $x = 1; } return $x; } }'
    );
    ok(defined $m, 'if-no-else parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'if-no-else schedule is balanced');

    my @kinds = _kinds($sched);
    is(scalar(grep { $_ eq 'else' } @kinds), 0,
       'no else marker when source had no else');
    is(scalar(grep { $_ eq 'block_open' } @kinds), 1,
       'one block_open');
    is(scalar(grep { $_ eq 'block_close' } @kinds), 1,
       'one block_close');
}

# --- Test 3: postfix if ---
{
    my $m = _parse_method('class C { method m { my $x = 0; $x = 1 if $x; return $x; } }');
    ok(defined $m, 'postfix if parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'postfix-if schedule is balanced');

    my @kinds = _kinds($sched);
    # Should have one block_open(if) wrapping the body expr.
    is(scalar(grep { $_ eq 'block_open' }  @kinds), 1, 'postfix-if: one block_open');
    is(scalar(grep { $_ eq 'block_close' } @kinds), 1, 'postfix-if: one block_close');
}

done_testing();
