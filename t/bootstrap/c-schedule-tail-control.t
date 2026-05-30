# ABOUTME: Phase 7d smoke test for a control-flow node at the tail (implicit-return) position.
# ABOUTME: Verifies _emit_c_schedule_item handles synthetic Return wrapping If/Loop/TryCatch via _expand_node.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);
use Chalk::Bootstrap::Perl::Target::C;
use Chalk::IR::Scheduler::EagerPinning;

# Construct a minimal class whose method has a control-flow value
# at the tail position (the implicit return).
my $src = <<'PERL';
class Test::VarDeclControl {
    method tail_if($self, $x) {
        if ($x) { 1 } else { 0 }
    }
}
PERL

my $mop = Chalk::MOP->new;
Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
my ($ir, $sa, $ctx) = parse_perl_source($src);
ok(defined $ctx, 'parse succeeds');

my $mop_class;
for my $cls ($mop->classes) {
    next if $cls->name eq 'main';
    $mop_class = $cls;
}
ok(defined $mop_class, 'class found in MOP');

SKIP: {
    skip 'no class', 1 unless defined $mop_class;
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::VarDeclControl',
    );
    my $result = eval { $target->_generate_c_files($ir, $sa, $ctx) };
    ok(defined $result, '_generate_c_files succeeds for tail-if method') or do {
        diag "Error: $@";
    };
}

# A method whose body is a try/catch with a `die` in the catch arm has
# BOTH a synthetic Return (the structured try/catch exit) and an Unwind
# (the catch arm's die) as exit candidates. When their control-chain
# lengths tie, _pick_outer_return must choose the Return — the true
# method exit — not the Unwind. Picking the Unwind collapses the whole
# try/catch to a bare `die $e` at the method tail.
{
    my $tc_src = <<'PERL';
class Test::TryCatchTail {
    method m($self) {
        try { 1 } catch ($e) { die $e }
    }
}
PERL

    my $tc_mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($tc_mop);
    my ($tc_ir, $tc_sa, $tc_ctx) = parse_perl_source($tc_src);
    ok(defined $tc_ctx, 'try/catch-tail source parses');

    my $tc_class;
    for my $cls ($tc_mop->classes) {
        next if $cls->name eq 'main';
        $tc_class = $cls;
    }
    ok(defined $tc_class, 'try/catch-tail class found in MOP');

    SKIP: {
        skip 'no class', 1 unless defined $tc_class;
        my ($meth) = grep { $_->name eq 'm' } $tc_class->methods;
        skip 'no method m', 1 unless defined $meth;

        my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($meth);
        my @items = $sched->items->@*;
        my $last  = $items[-1];
        my $node  = (defined $last && $last->can('node')) ? $last->node : undef;
        my $op    = (defined $node && blessed($node)) ? $node->operation : '(none)';

        isnt($op, 'Unwind',
            'try/catch-tail method exit is not Unwind (die does not become the method tail)');
    }
}

done_testing();
