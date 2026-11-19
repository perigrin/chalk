# ABOUTME: A reference T2 does not make (a glob's, a field's) refuses a program only where its value
# ABOUTME: may reach a scalar deref -- through calls, returns, elements, globals -- not merely beside one.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

require Chalk::CodeGen::Pipeline;

my $select = sub ($graphs, $mop) {
    my $g = $graphs->{'main::__PROGRAM__'} or return ();
    my $ret = $g->returns->[0] or return ();
    return ([ 'main::__PROGRAM__', $ret ]);
};

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

sub through_llvm ($pl) {
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

my $REACHES = qr/\Alower: GAP: T2: out of its slices \(\Qa scalar deref where a reference T2 does not make may reach it\E\)/;

# (a) THE TWO NEVER MEET: perl's answer. Each was refused while the check
# asked only whether both were somewhere in the program.
for my $src (
    # a glob's reference read by ref, beside a deref of a `my` scalar's
    q{my $g = \*STDOUT; print ref($g), "\n"; my $s = 5; my $r = \$s; $$r = 7; print "$s $$r\n";},
    # Symbol::gensym's shape: a glob's reference a sub never called returns
    q{sub gensym { my $n = shift; my $g = \*{"main::GEN" . $n}; return $g }
my $s = "a"; my $r = \$s; $$r .= "b"; print "$s\n";},
    # a reference to a class's field, read by ref only, in a method never called
    q{use v5.38; use experimental 'class'; class P { field $x = 3; method fr { my $q = \$x; return ref($q) } }
my $s = 4; my $r = \$s; print $$r + 1, "\n";},
) {
    my $pl = write_pl($src);
    my $got = eval { through_llvm($pl) };
    is($got, scalar qx($^X $pl 2>&1), "never meet, perl's answer: $src") or diag $@;
}

# (b) THEY MEET where they stand, (c) or through a call, a return, an element,
# a global, a hash, a parameter: refused, by the check's name.
for my $src (
    q{my $g = \*STDOUT; my $s = 5; my $r = @ARGV ? \$s : $g; print $$r // "u", "\n";},
    q{sub id { return $_[0] } my $s = 5; print ${ id(\*STDOUT) } // "u", "\n";},
    q{sub d { my ($r) = @_; return $$r } print d(\*STDOUT) // "u", "\n";},
    q{sub mk { return \*STDERR } my $r = mk(); print $$r // "u", "\n";},
    q{my @a = (\*STDOUT); print ${ $a[0] } // "u", "\n";},
    q{my @a; push @a, \*STDOUT; print ${ $a[-1] } // "u", "\n";},
    q{my %h; $h{k} = \*STDOUT; print ${ $h{k} } // "u", "\n";},
    q{our $G = \*STDOUT; sub rd { return ${$G} } print rd() // "u", "\n";},
    q{package O { sub new { bless { g => \*STDOUT }, shift } sub g { $_[0]{g} } } my $o = O->new; print ${ $o->g } // "u", "\n";},
    # through a code value: its sub's return, its argument
    q{sub mk { return \*STDERR } my $f = \&mk; print ${ $f->() } // "u", "\n";},
    q{my $c = sub { ${ $_[0] } }; print $c->(\*STDOUT) // "u", "\n";},
    # a closure's capture, a map's topic, a foreach alias
    q{my $g = \*STDOUT; my $c = sub { ${$g} }; print $c->() // "u", "\n";},
    q{print map { ${$_} // "u" } (\*STDOUT); print "\n";},
    q{for my $r (\*STDOUT) { print ${$r} // "u", "\n" }},
    # a file lexical stored, read in a named sub
    q{my $g; $g = \*STDOUT; sub r { ${$g} } print r() // "u", "\n";},
) {
    my $pl = write_pl($src);
    my $got = eval { through_llvm($pl) };
    ok(!defined $got, "T2 lowers no module where they meet: $src");
    like($@, $REACHES, "refused by the check's name: $src");
}

done_testing;
