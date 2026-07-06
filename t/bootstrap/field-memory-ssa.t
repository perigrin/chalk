# ABOUTME: End-to-end memory-SSA phase 2c: object field read/store WAR ordering (lli == perl).
# ABOUTME: FieldAccess is already a MUTABLE_READ_OP (re-lowers per program point); this locks that in.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

skip_all "lli not found"       unless -x $LLI;
skip_all "perl 5.42 not found" unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::CodeGen::Harness::MdtestCorpus;
require Chalk::Target::LLVM;

# Lower a hand-built IR block through the corpus path and run it under lli.
# Returns the printed integer (e.g. 5 from "Int:5"), or ('gap', $err).
sub lower_and_run ($ir) {
    my ($rn, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir);
    my $ll = eval {
        Chalk::Target::LLVM->lower($rn, (defined $mop ? (mop => $mop) : ()));
    };
    return ('gap', $@) if $@;
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    chomp $out;
    my $val = ($out =~ /Int:(-?\d+)/) ? $1 : $out;
    return ('value', $val);
}

# Perl oracle for the WAR class: snap reads $a before the store (5), b after (99).
sub perl_war ($method) {
    my $src = <<"PERL";
use v5.42; use experimental 'class';
class WAR { field \$a=5; field \$snap; field \$b;
  ADJUST { \$snap=\$a; \$a=99; \$b=\$a }
  method snap { \$snap } method b { \$b } }
print WAR->new->$method;
PERL
    my ($fh, $t) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $o = qx($PERL $t 2>&1); chomp $o; return $o;
}

# The WAR class IR block. Field a defaults to 5. ADJUST body, in order:
#   snap = a   (PRE-store read of a -> must snapshot 5)
#   a = 99     (the store)
#   b = a      (POST-store read of a -> must observe 99)
# The two reads of a hash-cons to ONE FieldAccess(field_index:0) node. Because
# FieldAccess is a MUTABLE_READ_OP (Target::LLVM.pm), lower_value bypasses the
# value cache for it and re-lowers it at each consumption point, so the shared
# node emits two distinct field-load instructions — one before the store (5),
# one after (99). This test characterizes that the 2a/2b cache-bypass machinery
# already covers the object-field WAR hazard; no FieldAccess-specific fix exists.
# $method / $body_fidx select which reader we invoke (snap=field1, b=field2).
sub war_ir ($method, $body_fidx) {
    return <<"IR";
%cls    = MOP::Class(name: "WAR")
%c5     = Constant(5) :Int
%mf_a   = MOP::Field(class: %cls, name: "a",    fieldix: 0, param: false, reader: false, has_default: true, default_value: %c5, type: "Int")
%mf_snp = MOP::Field(class: %cls, name: "snap", fieldix: 1, param: false, reader: false, has_default: false, type: "Int")
%mf_b   = MOP::Field(class: %cls, name: "b",    fieldix: 2, param: false, reader: false, has_default: false, type: "Int")
%fa_a1  = FieldAccess(field_index: 0, field_stash: "WAR") :Int
%snp_lv = FieldAccess(field_index: 1, field_stash: "WAR") :Int
%fw_snp = Assign(%snp_lv, %fa_a1) :Int
%a_lv   = FieldAccess(field_index: 0, field_stash: "WAR") :Int
%c99    = Constant(99) :Int
%fw_a   = Assign(%a_lv, %c99) :Int
%fa_a2  = FieldAccess(field_index: 0, field_stash: "WAR") :Int
%b_lv   = FieldAccess(field_index: 2, field_stash: "WAR") :Int
%fw_b   = Assign(%b_lv, %fa_a2) :Int
%adj    = MOP::Adjust(class: %cls, body: [%fw_snp, %fw_a, %fw_b])
%fa_rd  = FieldAccess(field_index: $body_fidx, field_stash: "WAR") :Int
%mi     = MOP::Method(class: %cls, name: "$method", body: %fa_rd, return_repr: "Int")
%new_o  = Call(dispatch_kind: "method", name: "new", class: "WAR") :Object
%result = Call(%new_o, dispatch_kind: "method", name: "$method", class: "WAR") :Int
return %result
IR
}

subtest 'field read BEFORE a store snapshots the pre-store value (WAR, already covered)' => sub {
    my $oracle = perl_war('snap');
    is($oracle, '5', 'perl oracle: snap == 5') or return;
    my ($kind, $out) = lower_and_run(war_ir('snap', 1));
    is($kind, 'value', 'lowered (not a GAP)') or return;
    is($out, '5', 'lli returns 5 (the pre-store field value), not 0 or 99');
};

subtest 'field read AFTER a store observes the stored value' => sub {
    my $oracle = perl_war('b');
    is($oracle, '99', 'perl oracle: b == 99') or return;
    my ($kind, $out) = lower_and_run(war_ir('b', 2));
    is($kind, 'value', 'lowered (not a GAP)') or return;
    is($out, '99', 'lli returns 99 (the post-store field value)');
};

subtest 'read-after-store within ADJUST stays correct (increment regression -> 11)' => sub {
    # Field a defaults to 10; ADJUST does a = a + 1 (a read of a, an Add, a store
    # back); method val reads a. The post-store read MUST observe 11, proving that
    # re-lowering a field read after a store to the same field sees the new value
    # (not the stale pre-store 10).
    my $ir = <<"IR";
%cls    = MOP::Class(name: "Counter")
%c10    = Constant(10) :Int
%mf_a   = MOP::Field(class: %cls, name: "a", fieldix: 0, param: false, reader: false, has_default: true, default_value: %c10, type: "Int")
%fa_rd  = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%c1     = Constant(1) :Int
%sum    = Add(%fa_rd, %c1) :Int
%a_lv   = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%fw_a   = Assign(%a_lv, %sum) :Int
%adj    = MOP::Adjust(class: %cls, body: [%fw_a])
%fa_val = FieldAccess(field_index: 0, field_stash: "Counter") :Int
%mi     = MOP::Method(class: %cls, name: "val", body: %fa_val, return_repr: "Int")
%new_o  = Call(dispatch_kind: "method", name: "new", class: "Counter") :Object
%result = Call(%new_o, dispatch_kind: "method", name: "val", class: "Counter") :Int
return %result
IR
    my ($kind, $out) = lower_and_run($ir);
    is($kind, 'value', 'lowered (not a GAP)') or return;
    is($out, '11', 'lli returns 11 (10 + 1), post-store read sees the incremented value');
};

done_testing();
