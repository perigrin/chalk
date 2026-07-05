# ABOUTME: Guards the stmt-effect element-store Assign repr inference through control_in.
# ABOUTME: A store whose value's repr is derived by the propagation pass must type the Assign.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# Load the B::SoN JSON for a driver snippet and return the (single) element-store
# Assign node (the Return's control_in) from main::corpus_case.
sub store_assign ($driver) {
    my $src = "package main;\nsub corpus_case { $driver }\n";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    my ($graphs, $mop) = from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return undef;
    my $ret = $g->returns->[0] or return undef;
    my $c = $ret->control_in;
    return ($c && $c->operation eq 'Assign') ? $c : undef;
}

subtest 'a literal-value store types the Assign Int' => sub {
    my $as = store_assign('my @a = (1,2,3); $a[0] = 42; $a[0]');
    ok(defined $as, 'the store Assign is reachable via control_in') or return;
    is($as->representation, 'Int', 'Assign(store of 42) is Int');
};

subtest 'a computed-value store still types the Assign (repr via control_in closure)' => sub {
    # `$a[0] = $b[0]` stores a Subscript whose repr is inferred by the
    # propagation pass. The store Assign is control_in-only (not in $g->nodes),
    # so the pass must reach it AND its value subtree via the control-chain
    # closure -- else the Assign stays untyped and hits the backend NO-REPR guard
    # (a non-functional GAP for every store of a computed value).
    my $as = store_assign('my @a = (1,2,3); my @b = (5,6,7); $a[0] = $b[0]; $a[0]');
    ok(defined $as, 'the store Assign is reachable') or return;
    is($as->representation, 'Int', 'Assign(store of $b[0]) is typed Int, not undef');
    is($as->inputs->[-1]->representation, 'Int', 'the stored Subscript value is Int');
};

done_testing();
