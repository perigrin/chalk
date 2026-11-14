# ABOUTME: One pvm-corpus case through T2 alone (never the Context fallback):
# ABOUTME: SAME, DIFFERS, or REFUSED with T2's reason. Cases are named file:N or cNNN.
package Chalk::CodeGen::Harness::T2Case;
use v5.42.0;
use File::Temp qw(tempdir);
use Exporter 'import';
our @EXPORT_OK = qw(cases case_by_id run_case);

my $SON    = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $CORPUS = $ENV{SON_CORPUS} // "$SON/../t/corpus/mdtest/pvm";
my $LLI    = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';

# cases() -> ({ id, cid, file, src, want }, ...): the census's cases, in the
# census's order (cid c001.. is the census numbering; id is file:N, stable when
# other files change).
sub cases () {
    require lib; lib->import("$SON/../tools/lib");
    require PvmCorpus;
    my (@out, %n);
    my $i = 0;
    for my $c (PvmCorpus::read_cases($CORPUS)) {
        ( my $f = $c->{file} ) =~ s{.*/}{}; $f =~ s/\.md\z//;
        push @out, { %$c, id => "$f:" . ++$n{$f}, cid => sprintf('c%03d', ++$i) };
    }
    return @out;
}

sub case_by_id ($id) {
    my ($c) = grep { $_->{id} eq $id || $_->{cid} eq $id } cases();
    return $c;
}

# run_case($case) -> { verdict => SAME|DIFFERS|REFUSED, why, got, want }
sub run_case ($c) {
    require Chalk::CodeGen::Pipeline;
    my $dir = tempdir(CLEANUP => 1);
    open my $o, '>', "$dir/p.pl" or die $!; print $o $c->{src}; close $o;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $dir/p.pl 2>/dev/null);
    return { verdict => 'REFUSED', why => 'B::SoN produced no graph' } unless $json =~ /\S/;
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) = eval { Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1) };
    $err //= $@ if $@;
    return { verdict => 'REFUSED', why => "load: $err" =~ s/\n.*//sr } if $err;
    my $u = ( $units // [] )->[0] or return { verdict => 'REFUSED', why => 'no program graph' };
    # T2 ALONE: a program the fallback lowered is one T2 refused.
    return { verdict => 'REFUSED', why => ( $u->{path_why} // $u->{err} // 'declined' ) =~ s/\n.*//sr }
        unless $u->{ok} && ( $u->{path} // '' ) eq 't2';
    open my $l, '>', "$dir/p.ll" or die $!; binmode $l, ':utf8'; print $l $u->{ll}; close $l;
    my $got = qx(timeout 60 $LLI $dir/p.ll 2>/dev/null </dev/null);
    return { verdict => $got eq $c->{want} ? 'SAME' : 'DIFFERS', got => $got, want => $c->{want} };
}

1;
