# ABOUTME: Phase 2 Step A diagnostic — characterizes the during-parse control predecessor gap.
# ABOUTME: Documents that without the Block rebuild, statement N+1 sees Start, not statement N.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr blessed);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use TestPipeline qw(parse_perl_source);

# Parse a method body and return its IR statement nodes in source order.
sub method_body_stmts ($src) {
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    return unless defined $ctx;
    my ($cls) = grep { $_->name ne 'main' } $mop->classes;
    return unless defined $cls;
    my ($m) = $cls->methods;
    return unless defined $m && $m->can('body');
    my $body = $m->body;
    return unless ref($body) eq 'ARRAY';
    return grep { ref $_ } $body->@*;
}

my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        my $y = 2;
    }
}
PERL

# With the Block rebuild ACTIVE, the control chain is correct: statement 2's
# control input is statement 1's node. This is the chain any during-parse
# threading must reproduce (the Step A differential target).
{
    my @stmts = method_body_stmts($src);
    is(scalar(@stmts), 2, 'method body has two statements (rebuild active)');

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        is(
            refaddr($s2->inputs->[0]), refaddr($s1),
            'rebuild active: second statement control input is the first statement node'
        );
    }
}

# The diagnosis: with the rebuild DISABLED, the during-parse value the action
# sees for statement 2's control predecessor is Start, NOT statement 1. The
# rebuild is what repairs the chain; the during-parse threading does not yet
# deliver the predecessor. This pins the bug the rebuild masks.
{
    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 2, 'method body has two statements (rebuild disabled)');

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        my $ctrl2 = $s2->inputs->[0];
        is(
            ( blessed($ctrl2) && $ctrl2->can('operation') ? $ctrl2->operation : 'undef' ),
            'Start',
            'rebuild disabled: second statement control predecessor is the bare Start seed (the gap)'
        );
    }
}

# Step A goal (BLOCKED — see docs/plans/2026-06-01 plan and the Phase 2 Step A
# report): during-parse control_head threading at Earley prediction should make
# the rebuild-disabled chain identical to the rebuild-active chain. A seed-at-
# prediction prototype proved insufficient: the bare/refined VarDecl identity
# split plus the add() tie-break delivers the pre-init head, and non-VarDecl
# statements never read control_head into inputs[0] at all (they are entirely
# rebuild-dependent). Marked TODO until the merge/action gaps are closed.
TODO: {
    local $TODO = 'Step A during-parse control threading not yet viable; rebuild remains the source of truth';

    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($src);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        is(
            refaddr($s2->inputs->[0]), refaddr($s1),
            'threading (rebuild disabled) reproduces the rebuild-active chain'
        );
    }
}

# Step (b): the side-effect statement actions must consume $ctx->control_head
# into their control input AT CONSTRUCTION, like VarDecl/Return/Unwind already
# do. This step does NOT fix cross-statement chaining (the lateral-seed gap) —
# it only makes the action READ whatever control_head is present at fire time.
#
# For a single statement-position Call whose predecessor IS Start (the seed),
# control_head is correct at construction, so the action — with the rebuild
# DISABLED — must set the Call's control_in to that Start. Today it is undef:
# the action layer is structurally incapable of consuming control. This test
# pins that the action now sets it on its own.
{
    my $single = <<'PERL';
class T {
    method m($self) {
        foo();
    }
}
PERL

    Chalk::Bootstrap::Perl::Actions->disable_control_rebuild;
    my @stmts = method_body_stmts($single);
    Chalk::Bootstrap::Perl::Actions->enable_control_rebuild;

    is(scalar(@stmts), 1, 'single side-effect statement (rebuild disabled)');

  SKIP: {
        skip 'parse did not yield one statement', 1 unless @stmts == 1;
        my ($call) = @stmts;
        my $ctrl = $call->can('control_in') ? $call->control_in : undef;
        is(
            ( blessed($ctrl) && $ctrl->can('operation') ? $ctrl->operation : 'undef' ),
            'Start',
            'rebuild disabled: statement-position Call consumes control_head (Start) at construction'
        );
    }
}

done_testing;
