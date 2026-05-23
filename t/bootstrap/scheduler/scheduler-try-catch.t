# ABOUTME: Tests EagerPinning scheduler try/catch structured expansion.
# ABOUTME: Phase 4d — TryCatch becomes block_open(try) / try-body / catch / catch-body / block_close.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SchedulerTryCatchTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::SchedulerTryCatchTest::grammar();
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

# --- try/catch with both arms populated ---
{
    my $m = _parse_method(
        'class C { method m { try { my $x = 1; } catch ($e) { my $y = 2; } return 0; } }'
    );
    ok(defined $m, 'try/catch parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'try/catch schedule balanced');

    my @kinds = _kinds($sched);
    my @forms = _forms($sched);

    is(scalar(grep { $_ eq 'block_open' }  @kinds), 1, 'one block_open');
    is(scalar(grep { $_ eq 'block_close' } @kinds), 1, 'one block_close');
    is(scalar(grep { $_ eq 'catch' }       @kinds), 1, 'one catch marker');

    my $open  = (grep { $kinds[$_] eq 'block_open'  } 0..$#kinds)[0];
    my $catch = (grep { $kinds[$_] eq 'catch'        } 0..$#kinds)[0];
    my $close = (grep { $kinds[$_] eq 'block_close' } 0..$#kinds)[0];
    is($forms[$open],  'try', 'block_open form is try');
    is($forms[$close], 'try', 'block_close form is try');
    cmp_ok($open,  '<', $catch, 'open < catch');
    cmp_ok($catch, '<', $close, 'catch < close');
}

done_testing();
