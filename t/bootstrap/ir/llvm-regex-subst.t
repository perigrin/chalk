# ABOUTME: G6 s/// substitution — RegexSubst lowers to match (group-0 bounds) +
# ABOUTME: Str splice (malloc+memcpy); $N in the replacement consumes explicit captures.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

sub lli_run {
    my ($ret, %lower_opts) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1, %lower_opts);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out = `$LLI $f 2>&1`;
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out\n--- .ll ---\n$ll" if $exit;
    # No chomp: the program prints exactly the value and nothing else, so
    # every byte of stdout IS the result. A trailing newline in the subject
    # is DATA here -- chomping would erase the difference between "abcX"
    # and "abcX\n", which is exactly what the s/$/X/ case is testing.
    return ($out, $ll);
}

sub _mk { Chalk::IR::NodeFactory->new }

# Observe a value the way a program does: PRINT it, then return undef. A
# program's observable contract is stdout plus exit status; it has no side
# channel that hands a value back to a harness.
sub print_and_return {
    my ($f, $value) = @_;

    # Print takes a Str, so a non-Str value is bridged with an explicit
    # Coerce -- the same node a source program's producer inserts.
    my $arg  = $value;
    my $repr = $value->stamp;
    if (!defined $repr || $repr ne 'Str') {
        $arg = $f->make('Coerce', inputs => [$value],
            from_repr => $repr, to_repr => 'Str');
        $arg->set_stamp('Str');
    }

    my $print = $f->make('Print', inputs => [$arg]);
    $print->set_control_in($f->make_cfg('Start'));

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);
    return $ret;
}

# Build RegexSubst($subject =~ s/$pattern/$replacement/) -> Str (the result).
sub subst_node {
    my ($f, $subject, $pattern, $replacement) = @_;
    my $subj = $f->make('Constant', value => $subject, const_type => 'string');
    $subj->set_stamp('Str');
    my $s = $f->make('RegexSubst',
        pattern => $pattern, replacement => $replacement, flags => '',
        inputs => [$subj]);
    $s->set_stamp('Str');
    return $s;
}

sub try_subst {
    my ($subject, $pattern, $replacement, $want, $label) = @_;
    my $f = _mk();
    my $s = subst_node($f, $subject, $pattern, $replacement);
    my $ret = print_and_return($f, $s);
    my ($out, $ll) = eval { lli_run($ret) };
    if ($@) { fail("$label: lowering/lli failed: $@"); return }
    is($out, $want, $label);
    return $ll;
}

# R3 corpus shape: literal replace, first match.
subtest 's/foo/baz/ on "foobar" => "bazbar"' => sub {
    my $ll = try_subst('foobar', 'foo', 'baz', 'bazbar',
        's/foo/baz/ replaces the first match');
    return unless defined $ll;
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'substitution .ll is libperl-free');
};

subtest 's/// non-match leaves the subject unchanged' => sub {
    try_subst('foobar', 'xyz', 'baz', 'foobar',
        's/xyz/baz/ does not change "foobar"');
};

subtest 's/// with different lengths (grow and shrink)' => sub {
    try_subst('ab',    'b',   'XYZ', 'aXYZ', 'replacement longer than match');
    try_subst('aXYZb', 'XYZ', '',    'ab',   'empty replacement deletes the match');
};

subtest 's/// replaces only the FIRST match (no /g)' => sub {
    try_subst('aXaXa', 'X', 'o', 'aoaXa', 'only the first X is replaced');
};

subtest 's/(o+)/[$1]/ — explicit capture consumed in the replacement' => sub {
    try_subst('foobar', '(o+)', '[$1]', 'f[oo]bar',
        '$1 in the replacement is the captured run');
};

subtest 's/(\\w+)-(\\w+)/$2_$1/ — two captures, reordered' => sub {
    try_subst('ab-cd', '(\\w+)-(\\w+)', '$2_$1', 'cd_ab',
        '$2 and $1 reorder the halves');
};

# Review F3: an end-anchored empty pattern splices at the END (append), not
# at offset 0; with a trailing newline, before the newline (perl semantics).
subtest 's/$/X/ appends (and respects a trailing newline)' => sub {
    try_subst('abc',   '$', 'X', 'abcX',  's/$/X/ appends to "abc"');
    try_subst("abc\n", '$', 'X', "abcX\n", 's/$/X/ inserts before the trailing newline');
};

# Review: $10 must not silently parse as $1 . "0".
subtest 'replacement $N with multiple digits dies GAP' => sub {
    my $f = _mk();
    my $s = subst_node($f, 'a1b', '(\\d)', '[$10]');
    my $ret = $f->make_cfg('Return', inputs => [$s]);
    eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    like($@, qr/GAP/, '$10 in a 1-group replacement dies GAP (not $1 . "0")');
};

# Review: s/// literal-segment globals inside method bodies need the same
# class/method symbol prefix as @str_const_N (each method body lowers in a
# fresh Context whose counter restarts; module-scope @rxs_lit_0 would collide).
subtest 's/// in two method bodies: no duplicate @rxs_lit symbols' => sub {
    my $f = _mk();

    my $mk_body = sub {
        my ($text) = @_;
        my $subj = $f->make('Constant', value => $text, const_type => 'string');
        $subj->set_stamp('Str');
        my $s = $f->make('RegexSubst',
            pattern => 'o', replacement => 'LIT', flags => '', inputs => [$subj]);
        $s->set_stamp('Str');
        return $s;
    };

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Subby');
    my $m_a = $cls->declare_method('meth_a', return_type => 'Str');
    $m_a->graph->merge($f->make_cfg('Return', inputs => [$mk_body->('foo')]));
    my $m_b = $cls->declare_method('meth_b', return_type => 'Str');
    $m_b->graph->merge($f->make_cfg('Return', inputs => [$mk_body->('boo')]));
    $mop->seal;

    my $new_o = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Subby', param_names => [], inputs => []);
    $new_o->set_stamp('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'meth_a',
        class_name => 'Subby', inputs => [$new_o]);
    $call->set_stamp('Str');
    my $ret = print_and_return($f, $call);

    my ($out, $ll) = eval { lli_run($ret, mop => $mop) };
    ok(!$@, 'two method bodies with s/// lower + run (no duplicate symbol)')
        or do { diag("error: $@"); return };
    is($out, 'fLITo', 'method-body s/// result correct');
    my @defs = $ll =~ /^(\@\S*rxs_lit\S*) =/mg;
    my %seen; my @dups = grep { $seen{$_}++ } @defs;
    is(scalar @dups, 0, 'no duplicate @rxs_lit global symbols')
        or diag("duplicates: @dups");
};

done_testing;
