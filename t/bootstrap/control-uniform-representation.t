# ABOUTME: Proposal-2 — control is a uniform hash-excluded control_in decoration.
# ABOUTME: Pins Return/Unwind (step 1) and VarDecl (step 2) carrying control off inputs[0].
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

# Step 1: Return carries its control predecessor in the hash-excluded
# control_in field, NOT in inputs[0]. Its inputs hold only the value.
{
    my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        return $x;
    }
}
PERL
    my @stmts = method_body_stmts($src);
    my ($ret) = grep { blessed($_) && $_ isa Chalk::IR::Node::Return } @stmts;
    ok(defined $ret, 'found a Return node');

  SKIP: {
        skip 'no Return node', 3 unless defined $ret;
        is(scalar($ret->inputs->@*), 1,
            'Return inputs hold only the value (control is not in inputs)');
        ok(defined $ret->control_in,
            'Return control predecessor lives in control_in');
        is(refaddr($ret->value), refaddr($ret->inputs->[0]),
            'Return->value() reads inputs[0] (the value slot)');
    }
}

# Step 1: Unwind (die) carries its control in control_in; inputs hold only
# the exception-args arrayref.
{
    my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        die "boom";
    }
}
PERL
    my @stmts = method_body_stmts($src);
    my ($unw) = grep { blessed($_) && $_ isa Chalk::IR::Node::Unwind } @stmts;
    ok(defined $unw, 'found an Unwind node');

  SKIP: {
        skip 'no Unwind node', 2 unless defined $unw;
        is(scalar($unw->inputs->@*), 1,
            'Unwind inputs hold only the args (control is not in inputs)');
        ok(defined $unw->control_in,
            'Unwind control predecessor lives in control_in');
    }
}

# Step 2: VarDecl carries control in control_in, NOT inputs[0]. inputs hold
# [name, init]. Control is the hash-excluded decoration.
{
    my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        my $y = 2;
    }
}
PERL
    my @stmts = method_body_stmts($src);
    is(scalar(@stmts), 2, 'VarDecl body has two statements');

  SKIP: {
        skip 'parse did not yield two statements', 4 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        is(scalar($s1->inputs->@*), 2,
            'VarDecl inputs hold [name, init] (control is not in inputs)');
        ok(defined $s2->control_in,
            'VarDecl control predecessor lives in control_in');
        is(refaddr($s2->control_in), refaddr($s1),
            'second VarDecl control_in is the first VarDecl (rebuilt chain)');
        is(refaddr($s1->name), refaddr($s1->inputs->[0]),
            'VarDecl->name() reads inputs[0]');
    }
}

# Step 2 landmine: two textually-identical declarations in DIFFERENT control
# positions must be DISTINCT nodes (per-position identity), not hash-consed
# into one node fighting over a single control_in field.
{
    my $src = <<'PERL';
class T {
    method m($self) {
        my $x = 1;
        my $x = 1;
    }
}
PERL
    my @stmts = method_body_stmts($src);
    is(scalar(@stmts), 2, 'two identical decls yield two statements');

  SKIP: {
        skip 'parse did not yield two statements', 1 unless @stmts == 2;
        my ($s1, $s2) = @stmts;
        isnt(refaddr($s1), refaddr($s2),
            'identical decls in different positions are distinct nodes (per-position identity)');
    }
}

done_testing;
