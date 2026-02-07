# ABOUTME: Tests for ConciseTree container holding an ordered list of ConciseOps.
# ABOUTME: Covers push_op, concat, to_exec_string rendering, and op_count.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::ConciseOp;
use Chalk::Bootstrap::ConciseTree;

# --- Empty tree ---
{
    my $tree = Chalk::Bootstrap::ConciseTree->new();
    is($tree->op_count(), 0, 'empty tree has 0 ops');
    is($tree->to_exec_string(), '', 'empty tree renders to empty string');
    is_deeply($tree->ops(), [], 'empty tree ops is empty arrayref');
}

# --- push_op ---
{
    my $tree = Chalk::Bootstrap::ConciseTree->new();
    my $op = Chalk::Bootstrap::ConciseOp->new(name => 'enter', arity => '0');
    $tree->push_op($op);
    is($tree->op_count(), 1, 'push_op increases count');
    is($tree->ops()->[0]->name(), 'enter', 'pushed op accessible');
}

# --- Multiple push_op preserves order ---
{
    my $tree = Chalk::Bootstrap::ConciseTree->new();
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'enter', arity => '0'));
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'nextstate', arity => '0'));
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(
        name => 'const', arity => '$', type_info => 'IV 42',
    ));
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(
        name => 'padsv_store', arity => '2', type_info => '$x', private => '/LVINTRO',
    ));
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'leave', arity => '@'));

    is($tree->op_count(), 5, 'multiple push_op count');
    is($tree->ops()->[0]->name(), 'enter', 'first op is enter');
    is($tree->ops()->[4]->name(), 'leave', 'last op is leave');
}

# --- to_exec_string renders numbered lines ---
{
    my $tree = Chalk::Bootstrap::ConciseTree->new();
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'enter', arity => '0'));
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(
        name => 'const', arity => '$', type_info => 'IV 42',
    ));
    $tree->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'leave', arity => '@'));

    my $output = $tree->to_exec_string();
    my @lines = split /\n/, $output;
    is(scalar @lines, 3, 'to_exec_string has one line per op');
    like($lines[0], qr/^1\s+/, 'first line starts with 1');
    like($lines[0], qr/enter/, 'first line contains enter');
    like($lines[1], qr/^2\s+/, 'second line starts with 2');
    like($lines[1], qr/const/, 'second line contains const');
    like($lines[2], qr/^3\s+/, 'third line starts with 3');
    like($lines[2], qr/leave/, 'third line contains leave');
}

# --- concat merges trees ---
{
    my $tree1 = Chalk::Bootstrap::ConciseTree->new();
    $tree1->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'enter', arity => '0'));

    my $tree2 = Chalk::Bootstrap::ConciseTree->new();
    $tree2->push_op(Chalk::Bootstrap::ConciseOp->new(
        name => 'const', arity => '$', type_info => 'IV 1',
    ));
    $tree2->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'leave', arity => '@'));

    $tree1->concat($tree2);
    is($tree1->op_count(), 3, 'concat combines op counts');
    is($tree1->ops()->[0]->name(), 'enter', 'concat preserves first tree order');
    is($tree1->ops()->[1]->name(), 'const', 'concat appends second tree ops');
    is($tree1->ops()->[2]->name(), 'leave', 'concat preserves second tree order');
}

# --- concat does not modify source tree ---
{
    my $tree1 = Chalk::Bootstrap::ConciseTree->new();
    $tree1->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'enter', arity => '0'));

    my $tree2 = Chalk::Bootstrap::ConciseTree->new();
    $tree2->push_op(Chalk::Bootstrap::ConciseOp->new(name => 'leave', arity => '@'));

    $tree1->concat($tree2);
    is($tree2->op_count(), 1, 'concat does not modify source tree');
}

# --- Construction with initial ops ---
{
    my @ops = (
        Chalk::Bootstrap::ConciseOp->new(name => 'enter', arity => '0'),
        Chalk::Bootstrap::ConciseOp->new(name => 'leave', arity => '@'),
    );
    my $tree = Chalk::Bootstrap::ConciseTree->new(ops => \@ops);
    is($tree->op_count(), 2, 'construction with initial ops');
    is($tree->ops()->[0]->name(), 'enter', 'initial ops preserved');
}

done_testing;
