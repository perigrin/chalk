# ABOUTME: a list assignment to a field array or hash (`@l = (9)`, `%h = ()`,
# ABOUTME: `%h = $r->%*`) replaces its contents in place, as perl does.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

sub perl_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    return scalar qx($^X $pl 2>&1);
}

my $hdr = qq{use v5.42;\nuse experimental 'class';\n};
# pvm 247: assigned for their effect.
for my $src (
    $hdr . q{class Holder { field %registry; field @order;
  method register ($graphs) { %registry = $graphs->%*; @order = sort keys %registry; return $self }
  method clear { @order = (); return $self }
  method summary { return scalar(keys %registry) . ":" . join(",", @order) } }
my $h = Holder->new->register({ b => 2, a => 1 });
print $h->summary, " ", $h->clear->summary, "\n";
},
    $hdr . q{class L { field @l = (1, 2); method set { @l = (7, 8, 9); return scalar(@l) } method get { "@l" } }
my $o = L->new; print $o->set, " ", $o->get, "\n";
},
) {
    my $got = eval { through_llvm($src) };
    is($got, perl_of($src), "perl's answer: " . ( $src =~ s/\n/ /gr )) or diag $@;
}

# Its value read (pvm 141's methods return it): the count in scalar
# context, the elements in list context -- refused by name.
for my $src (
    $hdr . q{class K { field %h = (a => 1, b => 2); field @l = (1, 2, 3);
  method reset_h { %h = () } method reset_l { @l = (9) } method n { scalar(keys %h) . scalar(@l) } }
my $k = K->new; my $a = $k->reset_h; my @b = $k->reset_l; print $a, scalar(@b), $k->n, "\n";
},
    $hdr . q{class K { field %h; method set { %h = (a => 1, a => 2) } }
print scalar(K->new->set), "\n";
},
) {
    my $err = do { local $@; eval { through_llvm($src) }; $@ };
    like($err, qr/\A(?:load|lower): /, "refused: " . ( $src =~ s/\n/ /gr ));
}

done_testing;
