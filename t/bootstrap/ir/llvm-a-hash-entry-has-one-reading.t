# ABOUTME: A %HashEntry carries no tag, so a hash has one reading for its values:
# ABOUTME: a hash whose values disagree, or a read with none, is refused -- never wrong.
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

# EACH WAS A SILENT WRONG ANSWER OR A CRASH. A %HashEntry stores an i64
# payload and no tag; its reader decodes it by the read's stamp. A literal
# mixing Int and Num stored 1 as an i64 the Num read decoded as a double
# (4.94065645841247e-324 for 1); Int and Str segfaulted (backlog 6b1e3f07);
# a read whose stamp settled nothing was tagged Opaque and printed nothing.
for my $case (
    [ q{my %h = (a => 1, b => 2.5); print $h{a}, " ", $h{b}, "\n";}, "1 2.5\n", 'Int and Num values' ],
    [ q{my %h = (a => 1, b => "s"); print "$h{a} $h{b}\n";}, "1 s\n", 'Int and Str values' ],
    [ q{my %h = (a => 1, b => [1]); print $h{a}, "\n";}, "1\n", 'a value whose reading is not established' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    # A refusal is a die from load or lower; lli failing is a wrong answer.
    ok(defined $got ? $got eq $want : $@ =~ /^(?:load|lower): /,
        "$name: refused, or perl's answer")
        or diag defined $got ? "got: $got" : $@;
}

done_testing;
