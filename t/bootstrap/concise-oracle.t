# ABOUTME: Tests for ConciseTree::Oracle that invokes perl -MO=Concise,-exec and parses output.
# ABOUTME: Covers B::Concise output parsing and end-to-end oracle invocation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::ConciseOp;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Oracle;

my $oracle = Chalk::Bootstrap::ConciseTree::Oracle->new();
isa_ok($oracle, 'Chalk::Bootstrap::ConciseTree::Oracle');

# --- parse_concise_output: simple assignment ---
{
    my $text = <<'CONCISE';
1  <0> enter v
2  <;> nextstate(main 3 -e:1) v:us,*,&,{,$,fea=9,0x10
3  <$> const[IV 42] s
4  <1> padsv_store[$x:3,4] vKS/LVINTRO
5  <@> leave[1 ref] vKP/REFC
CONCISE

    my $tree = $oracle->parse_concise_output($text);
    isa_ok($tree, 'Chalk::Bootstrap::ConciseTree', 'parse returns ConciseTree');
    is($tree->op_count(), 5, 'parsed 5 ops from simple assignment');

    my $ops = $tree->ops();
    is($ops->[0]->name(), 'enter', 'op 1 is enter');
    is($ops->[0]->arity(), '0', 'enter has arity 0');

    is($ops->[1]->name(), 'nextstate', 'op 2 is nextstate');
    is($ops->[1]->arity(), ';', 'nextstate has arity ;');
    like($ops->[1]->type_info(), qr/main/, 'nextstate has type_info with main');

    is($ops->[2]->name(), 'const', 'op 3 is const');
    is($ops->[2]->arity(), '$', 'const has arity $');
    is($ops->[2]->type_info(), 'IV 42', 'const type_info is IV 42');

    is($ops->[3]->name(), 'padsv_store', 'op 4 is padsv_store');
    is($ops->[3]->arity(), '1', 'padsv_store has arity 1');
    like($ops->[3]->type_info(), qr/\$x/, 'padsv_store type_info contains $x');
    like($ops->[3]->private(), qr{/LVINTRO}, 'padsv_store has /LVINTRO private flag');

    is($ops->[4]->name(), 'leave', 'op 5 is leave');
    is($ops->[4]->arity(), '@', 'leave has arity @');
}

# --- parse_concise_output: compile-time only ---
{
    my $text = <<'CONCISE';
1  <0> enter v
2  <0> stub v
3  <@> leave[1 ref] vKP/REFC
CONCISE

    my $tree = $oracle->parse_concise_output($text);
    is($tree->op_count(), 3, 'parsed 3 ops from compile-time only');
    is($tree->ops()->[1]->name(), 'stub', 'op 2 is stub');
    is($tree->ops()->[1]->arity(), '0', 'stub has arity 0');
}

# --- parse_concise_output: array assignment ---
{
    my $text = <<'CONCISE';
1  <0> enter v
2  <;> nextstate(main 3 -e:1) v:us,*,&,{,$,fea=9,0x10
3  <0> pushmark s
4  <$> const[IV 1] s
5  <$> const[IV 2] s
6  <0> pushmark s
7  <0> padav[@arr:3,4] lRM*/LVINTRO
8  <2> aassign[t15] vKS
9  <@> leave[1 ref] vKP/REFC
CONCISE

    my $tree = $oracle->parse_concise_output($text);
    is($tree->op_count(), 9, 'parsed 9 ops from array assignment');

    my $ops = $tree->ops();
    is($ops->[2]->name(), 'pushmark', 'op 3 is pushmark');
    is($ops->[6]->name(), 'padav', 'op 7 is padav');
    like($ops->[6]->type_info(), qr/\@arr/, 'padav type_info contains @arr');
    like($ops->[6]->private(), qr{/LVINTRO}, 'padav has /LVINTRO');
    is($ops->[7]->name(), 'aassign', 'op 8 is aassign');
}

# --- parse_concise_output: ignores "-e syntax OK" preamble ---
{
    my $text = <<'CONCISE';
-e syntax OK
1  <0> enter v
2  <0> stub v
3  <@> leave[1 ref] vKP/REFC
CONCISE

    my $tree = $oracle->parse_concise_output($text);
    is($tree->op_count(), 3, 'ignores -e syntax OK preamble');
}

# --- parse_concise_output: hex sequence numbers ---
{
    # B::Concise uses hex for numbers >= 10
    my $text = <<'CONCISE';
1  <0> enter v
2  <;> nextstate(main 3 -e:1) v:us,*,&,{,$
3  <0> pushmark s
4  <$> const[IV 1] s
5  <$> const[IV 2] s
6  <$> const[IV 3] s
7  <$> const[IV 4] s
8  <$> const[IV 5] s
9  <$> const[IV 6] s
a  <$> const[IV 7] s
b  <0> padav[@arr:3,4] lRM*/LVINTRO
c  <2> aassign[t15] vKS
d  <@> leave[1 ref] vKP/REFC
CONCISE

    my $tree = $oracle->parse_concise_output($text);
    is($tree->op_count(), 13, 'handles hex sequence numbers (a, b, c, d)');
}

# --- concise_for: live invocation ---
SKIP: {
    # Verify perl is available and supports B::Concise
    my $check = `perl -MO=Concise,-exec -e '1' 2>&1`;
    skip 'perl with B::Concise not available', 4 unless $check =~ /enter/;

    my $tree = $oracle->concise_for('use 5.42.0; my $x = 42;');
    isa_ok($tree, 'Chalk::Bootstrap::ConciseTree', 'concise_for returns ConciseTree');
    ok($tree->op_count() > 0, 'concise_for produces non-empty tree');

    # Verify expected ops are present
    my @op_names = map { $_->name() } $tree->ops()->@*;
    ok((grep { $_ eq 'enter' } @op_names), 'live output contains enter');
    ok((grep { $_ eq 'leave' } @op_names), 'live output contains leave');
}

done_testing;
