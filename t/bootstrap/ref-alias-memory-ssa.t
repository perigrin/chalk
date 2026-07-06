# ABOUTME: End-to-end memory-SSA phase 2d: aliased element store (store via a ref, read via the array name).
# ABOUTME: `my @a=(...); my $r=\@a; $r->[0]=42; $a[0]` -- \@a and @a share backing storage, so the store is visible.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

skip_all "perl5-son not found"  unless -f "$SON/B/SoN.pm";
skip_all "lli not found"        unless -x $LLI;
skip_all "perl 5.42 not found"  unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::IR::Serialize::JSON;
require Chalk::Target::LLVM;

# Drive a snippet through B::SoN -> Chalk load -> LLVM lower -> lli; return
# ('value', $lli_out) or ('gap', $err) or ('err', $why).
sub lower_and_run ($body) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh "package main;\nsub corpus_case { $body }\n";
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return ('err', 'no JSON') unless $json =~ /\S/;
    my ($graphs, $mop) = Chalk::IR::Serialize::JSON::from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return ('err', 'no graph');
    my $ll = eval {
        Chalk::Target::LLVM->lower($g->returns->[0],
            (defined $mop ? (mop => $mop) : ()));
    };
    return ('gap', $@) if $@;
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    chomp $out;
    return ('value', $out);
}

subtest 'R12: aliased element store via ref is visible through the array name' => sub {
    # $r = \@a shares backing storage with @a (Perl semantics); the store
    # through $r->[0] must be visible to $a[0]. perl oracle = 42.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $r=\@a; $r->[0]=42; $a[0]');
    is($kind, 'value', 'lowered (not a GAP)') or return;
    is($out, 'Int:42', 'lli returns 42 (the aliased store), not the pre-store 1');
};

subtest 'non-aliased same-name store/read still works (regression)' => sub {
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); $a[0]=42; $a[0]');
    is("$kind:$out", 'value:Int:42', 'same-name element store/read -> 42');
};

subtest 'aliased store does not clobber a sibling slot' => sub {
    # After $r->[0]=42, a[1] must still be its initializer value 2 -- the
    # alias store wrote only slot 0, not slot 1.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $r=\@a; $r->[0]=42; $a[1]');
    is("$kind:$out", 'value:Int:2', 'sibling slot untouched by the aliased store -> 2');
};

subtest 'aliased HASH store via ref is visible through the hash name' => sub {
    # The Ref unwrap resolves the HashRef container the same way as ArrayRef:
    # $r = \%h shares backing storage with %h, so $r->{a}=9 is visible via $h{a}.
    # perl oracle = 9. (Was an Int:1 miscompile before 2d -- zhi 019f330b.)
    my ($kind, $out) = lower_and_run('my %h=(a=>1); my $r=\%h; $r->{a}=9; $h{a}');
    is("$kind:$out", 'value:Int:9', 'aliased hash store visible through the name -> 9');
};

subtest 'read via a ref ($r->[0] as rvalue) is not lowered yet' => sub {
    # The 2d fix resolves the Ref container on the STORE lvalue path and in
    # _container_ptr, but _lower_subscript does not unwrap a Ref container on the
    # read path, so a bare rvalue read through a ref GAPs LOUDLY (honest, never a
    # miscompile). Filed as a follow-up. When the read-side unwrap lands, drop
    # the todo and assert Int:42.
    todo 'read-via-ref rvalue unwrap not implemented (follow-up)' => sub {
        my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $r=\@a; $r->[0]=42; $r->[0]');
        is("$kind:$out", 'value:Int:42', 'read through the ref sees the aliased store -> 42');
    };
};

done_testing();
