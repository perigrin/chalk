# ABOUTME: a constant-key read of %main:: answers as perl does where nothing the
# ABOUTME: program runs can change the stash; elsewhere it is refused by name.
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

# Lowered, or the GAP that refused it.
sub try_llvm ($src) { my $r = eval { through_llvm($src) }; return defined $r ? $r : "REFUSED $@" }

sub perl_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    return scalar qx($^X $pl 2>&1);
}

# Whether an import or an `our` made a key, read as perl reads it (pvm 013
# 316 317 346).
for my $src (
    qq{use POSIX;\nprint "floor imported: ", (\$main::{"floor"} ? "yes" : "no"), "\\n";\n},
    qq{use POSIX ();\nprint "floor imported: ", (\$main::{"floor"} ? "yes" : "no"), "\\n";\n},
    qq{our \$answer = 42;\nprint "found: [", exists \$::{answer}, "]\\n";\nprint "gone: [", exists \$::{nosuch}, "]\\n";\nmy %stash = %::;\nprint "stash: [", exists \$stash{answer}, "]\\n";\n},
    qq{our \$answer = 42;\nprint \$::{answer}, "|", defined(\$::{nosuch}) ? 1 : 0, "\\n";\n},
) {
    is try_llvm($src), perl_of($src), "as perl: " . ( $src =~ s/\n/ /gr );
}

# What the program runs may change the stash: a delete from it, a symbolic
# deref, a runtime require of what may not be loaded. The loader names it;
# each is refused (here by an earlier GAP of its own, as it happens).
for my $case (
    [ qq{our \$x = 1;\ndelete \$::{x} if \$ENV{D};\nprint exists \$::{x} ? "y" : "n", "\\n";\n}, qr/a store to or delete from the stash/ ],
    [ qq{no strict;\nmy \$n = \$ENV{N} // "zz";\n\${\$n} = 1;\nprint exists \$::{zz} ? "y" : "n", "\\n";\n}, qr/a symbolic dereference/ ],
    [ qq{my \$m = \$ENV{M} // "Foo.pm";\neval { require \$m };\nprint exists \$::{zz} ? "y" : "n", "\\n";\n}, qr/a require of what is not known to be loaded/ ],
) {
    my ($src, $why) = @$case;
    like try_llvm($src), qr/\AREFUSED lower: GAP: /, "refused: " . ( $src =~ s/\n/ /gr );
    like $Chalk::IR::Serialize::JSON::STASH_CHANGES // '', $why, "...and the loader says why";
}

done_testing;
