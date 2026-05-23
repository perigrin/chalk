# ABOUTME: Tests EagerPinning scheduler elsif chain recognition.
# ABOUTME: Phase 4b — if/elsif/else collapses to block_open / elsif / [else] / block_close.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Scheduler::EagerPinning;
use Chalk::Bootstrap::Semiring::SemanticAction;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SchedulerElsifTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::SchedulerElsifTest::grammar();
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

# --- Test 1: if/elsif/else ---
{
    my $m = _parse_method(
        'class C { method m {
            my $x = 0;
            if ($x) { $x = 1; }
            elsif ($x) { $x = 2; }
            else { $x = 3; }
            return $x;
        } }'
    );
    ok(defined $m, 'if/elsif/else parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'if/elsif/else schedule is balanced');

    my @kinds = _kinds($sched);

    # Expect exactly ONE block_open and ONE block_close (the elsif
    # collapses, doesn't nest).
    is(scalar(grep { $_ eq 'block_open' }  @kinds), 1,
        'one block_open (elsif does not open a new block)');
    is(scalar(grep { $_ eq 'block_close' } @kinds), 1,
        'one block_close');
    is(scalar(grep { $_ eq 'elsif' } @kinds), 1, 'one elsif marker');
    is(scalar(grep { $_ eq 'else' }  @kinds), 1, 'one else marker');

    # Order: block_open ... elsif ... else ... block_close
    my $open  = (grep { $kinds[$_] eq 'block_open' }  0..$#kinds)[0];
    my $elsif = (grep { $kinds[$_] eq 'elsif' }       0..$#kinds)[0];
    my $else  = (grep { $kinds[$_] eq 'else' }        0..$#kinds)[0];
    my $close = (grep { $kinds[$_] eq 'block_close' } 0..$#kinds)[0];

    cmp_ok($open,  '<', $elsif, 'open < elsif');
    cmp_ok($elsif, '<', $else,  'elsif < else');
    cmp_ok($else,  '<', $close, 'else < close');
}

# --- Test 2: if/elsif (no final else) ---
{
    my $m = _parse_method(
        'class C { method m { my $x = 0; if ($x) { $x = 1; } elsif ($x) { $x = 2; } return $x; } }'
    );
    ok(defined $m, 'if/elsif parses');
    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'if/elsif schedule balanced');
    my @kinds = _kinds($sched);
    is(scalar(grep { $_ eq 'block_open' }  @kinds), 1, 'one block_open');
    is(scalar(grep { $_ eq 'elsif' }       @kinds), 1, 'one elsif');
    is(scalar(grep { $_ eq 'else' }        @kinds), 0, 'no else');
    is(scalar(grep { $_ eq 'block_close' } @kinds), 1, 'one block_close');
}

done_testing();
