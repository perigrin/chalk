# ABOUTME: A plain `sub` in a class is emitted as a real LLVM define, not a vtable slot.
# ABOUTME: Subs are reachable from the MOP registry; only methods need a vtable.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"  unless -f "$SON/B/SoN.pm";

my $dir = tempdir(CLEANUP => 1);

# Compile $src through the producer and lower it, returning the emitted LLVM IR.
sub ll_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    # package=main is load-bearing here, not tidiness: an unfiltered compile
    # drags in the ambient module set, and one of THOSE classes GAPs first
    # ("MOP::Method 'is_known' body root ... NO representation"), so the test
    # would report a refusal that has nothing to do with its subject.
    my $json = qx{$PERL -I$SON -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my ($graphs, $mop) = Chalk::IR::Serialize::JSON::from_json($json);
    my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
        or die "no entry graph for $name";
    my $ret = $g->returns->[0] or die "no Return node for $name";
    return Chalk::Target::LLVM->lower($ret, program_mode => 1,
        (defined $mop ? (mop => $mop) : ()));
}

my $SRC = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Widget {
    field $n :param = 0;
    method get { $n }
    sub helper { 7 }
}
print Widget->new(n => 1)->get, "\n";
PERL

# The load-bearing assertion: a plain sub in a class must reach the backend as
# something emittable. Before 1c the registry carried only {methods}, so a
# MOP::Sub replayed by 1b was inert -- the define was never emitted and a call
# to it would have targeted a symbol that does not exist.
subtest 'a class sub is emitted as a define' => sub {
    my $ll = eval { ll_for($SRC, 'clssub') };
    if (!defined $ll) {
        my $e = $@ // '';
        # A GAP is a loud refusal, which is acceptable-but-not-the-goal; a
        # SILENT omission is the defect. Distinguish them.
        like $e, qr/^GAP:/, 'refused loudly rather than silently dropping'
            or diag $e;
        return;
    }
    like $ll, qr/define\b[^\n]*\bWidget[^\n]*helper/,
        'a define is emitted for the class sub'
        or diag join "\n", grep { /define/ } split /\n/, $ll;
};

# The negative half, and the reason this is not just "add subs to the vtable":
# a sub has NO implicit invocant and is NOT dispatched, so it must not consume
# a vtable slot. A change that simply appended subs to {methods} would pass the
# assertion above and silently widen every vtable.
subtest 'a class sub does NOT take a vtable slot' => sub {
    my $ll = eval { ll_for($SRC, 'clsvt') };
    plan skip_all => 'lowering refused; covered by the subtest above'
        unless defined $ll;

    my ($vt) = grep { /^%Widget\.vt = type/ } split /\n/, $ll;
    ok defined $vt, 'Widget has a vtable' or return;
    # slot 0 is the class-name ptr; one method (`get`) means exactly 2 elements.
    my $slots = () = $vt =~ /i8\*/g;
    is $slots, 2,
        'vtable has class-name + ONE method slot (helper is not dispatched)'
        or diag $vt;
};

# THE `main` HALF IS DELIBERATELY NOT DONE, and this pins that rather than
# leaving it implied. main's subs ARE in the MOP (1b), but the INLINER still
# owns every direct call, so emitting a define for one duplicates the body
# instead of giving it a call path -- measured, corpus F9/F10/F11/F13 each
# printed their callee's output twice and the gate went 214 -> 207.
#
# main's class machinery must stay absent either way: it is never instantiated.
subtest 'main gets no class machinery, and no premature sub define' => sub {
    my $ll = eval { ll_for('sub helper { 7 } print helper(), "\n";', 'mainsub') };
    ok defined $ll, 'lowered' or do { diag $@; return };

    unlike $ll, qr/%main\.vt\b/,   'no vtable type for main';
    unlike $ll, qr/%main\.obj\b/,  'no object struct for main';
    unlike $ll, qr/\@main__vtable/,'no vtable global for main';

    # The staging assertion. Flip this to `like` in the step that retires the
    # inliner (plan step 5) -- that is the step that gives the define a caller.
    unlike $ll, qr/define\b[^\n]*\bmain__helper/,
        'no define for a file-level sub while the inliner still owns the call';
};

# The regression direction: a program with NO subs at all must emit exactly what
# it did before.
subtest 'a program with no subs is unchanged' => sub {
    my $ll = eval { ll_for('print 42, "\n";', 'nosubs') };
    ok defined $ll, 'lowered' or do { diag $@; return };
    unlike $ll, qr/%main\.vt\b/,      'still no vtable type for main';
    unlike $ll, qr/define[^\n]*main__/,'no stray sub defines';
};

# A CLASS sub is the opposite case and IS emitted: nothing inlines it, so
# without the define there is no way to reach it at all. The bilateral partner
# of the main subtest above -- together they pin WHY the two differ.
subtest 'a class sub emits exactly one define' => sub {
    my $ll = eval { ll_for($SRC, 'onedef') };
    ok defined $ll, 'lowered' or do { diag $@; return };
    my @defs = grep { /define\b[^\n]*Widget__helper/ } split /\n/, $ll;
    is scalar @defs, 1, 'exactly one define for the class sub'
        or diag join "\n", @defs;
};

done_testing;
