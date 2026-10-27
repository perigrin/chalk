# ABOUTME: `write` runs the handle's format: each picture line filled from its values
# ABOUTME: and printed (B::SoN -> chalk -> lli == perl), or refused by name.
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


# B::SoN makes the format a graph of `formline` calls and `write` a call of
# it; the loader found no sub by its name (pvm 293, 294).
for my $c (
    [ "format STDOUT =\na fixed report line\n.\nwrite;\nprint \"after write\\n\";\n" ],
    [ "our \$name = \"widget\"; our \$qty = 7;\nformat STDOUT =\n\@<<<<<<< \@>>>\n\$name,   \$qty\n.\nwrite;\nprint \"after write\\n\";\n" ],
    # Short values padded, long cut, a newline ends the value, undef empty,
    # centred, numeric; trailing spaces chopped.
    [ "our (\$a, \$b, \$c) = (\"ab\", \"x\\ny\", undef); our \$long = \"a-very-long-name\";\nformat STDOUT =\n[\@<<<<<] \@<<<< \@>>> \@|||||| \@##.## \@###\n\$a, \$b, \$c, \"mid\", 3.14159, -2.5\n\@<<<<<<< \@<<<<\n\$long, \$a\n.\nwrite; write;\n" ],
) {
    my ($src) = @$c;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $want = qx($^X $pl);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for: $src") or diag $@;
}

# A FIELD THAT CONTINUES (^<<<) or a line that repeats (~~) is refused.
{
    my $src = "our \$t = \"one two three four\";\nformat STDOUT =\n^<<<<<<<~~\n\$t\n.\nwrite;\n";
    my $got = eval { through_llvm($src) };
    like($@, qr/GAP/, "a ^ field is refused") or diag "got: " . ( $got // 'undef' );
}

# A FORMAT READING A LEXICAL: B::SoN dropped the program's store into it
# (it printed nothing for "mine"). Refused.
{
    my $src = "my \$lex = \"mine\";\nformat STDOUT =\n\@<<<<<<\n\$lex\n.\nwrite;\n";
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq "mine\n" ) || $@ =~ /GAP/, "a format reading a lexical: perl's answer or refused")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

done_testing;
