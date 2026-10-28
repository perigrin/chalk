# ABOUTME: a method on an object of a `class` that is known only at run time:
# ABOUTME: the one class that has it runs, or perl dies; else refused by name.
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


# The program at $pl through B::SoN, chalk's pipeline and lli: its output
# (not stderr: an uncaught die's message is not lowered), then its exit code.
sub through_llvm_file ($pl) {
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
    my $out = qx($LLI $ll 2>/dev/null);
    return $out . "exit " . ($? >> 8);
}

sub file_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    return $pl;
}


my $hdr = qq{use v5.36;\nuse feature 'class';\nno warnings 'experimental::class';\n};
# An element that is a Node or undef, guarded (pvm 248); unguarded, perl dies.
for my $src (
    $hdr . qq{class Node { field \$id :param; method id { return \$id } }\nsub ids (\$in) { return join(",", map { defined(\$_) ? \$_->id : "undef" } \$in->\@*) }\nprint ids([Node->new(id => 1), undef, Node->new(id => 3)]), "\\n";\n},
    $hdr . qq{class Node { field \$id :param; method id { return \$id } }\nsub ids (\$in) { return join(",", map { \$_->id } \$in->\@*) }\nprint "a\\n";\nprint ids([Node->new(id => 1), \$ENV{X}]), "\\n";\n},
) {
    my $pl = file_of($src);
    my $want = qx($^X $pl 2>/dev/null) . "exit " . ($? >> 8);
    my $got = eval { through_llvm_file($pl) } // "REFUSED $@";
    is($got, $want, "perl's answer: " . ( $src =~ s/\n/ /gr ));
}

# Two classes have the method: which one an object is, nothing here knows.
{
    my $src = $hdr . qq{class Cat { method id { 1 } }\nclass Dog { method id { 2 } }\nsub f (\$in) { return join(",", map { \$_->id } \$in->\@*) }\nprint f([Cat->new, Dog->new]), "\\n";\n};
    my $got = eval { through_llvm_file(file_of($src)) } // "REFUSED $@";
    like($got, qr/\AREFUSED lower: GAP: /, "refused by name: two classes have it");
}

done_testing;
