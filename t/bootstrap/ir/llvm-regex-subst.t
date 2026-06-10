# ABOUTME: G6 s/// substitution — RegexSubst lowers to match (group-0 bounds) +
# ABOUTME: Str splice (malloc+memcpy); $N in the replacement consumes explicit captures.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

sub lli_run {
    my ($ret) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out = `$LLI $f 2>&1`;
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out\n--- .ll ---\n$ll" if $exit;
    chomp $out;
    return ($out, $ll);
}

sub _mk { Chalk::IR::NodeFactory->new }

# Build RegexSubst($subject =~ s/$pattern/$replacement/) -> Str (the result).
sub subst_node {
    my ($f, $subject, $pattern, $replacement) = @_;
    my $subj = $f->make('Constant', value => $subject, const_type => 'string');
    $subj->set_representation('Str');
    my $s = $f->make('RegexSubst',
        pattern => $pattern, replacement => $replacement, flags => '',
        inputs => [$subj]);
    $s->set_representation('Str');
    return $s;
}

sub try_subst {
    my ($subject, $pattern, $replacement, $want, $label) = @_;
    my $f = _mk();
    my $s = subst_node($f, $subject, $pattern, $replacement);
    my $ret = $f->make_cfg('Return', inputs => [$s]);
    my ($out, $ll) = eval { lli_run($ret) };
    if ($@) { fail("$label: lowering/lli failed: $@"); return }
    is($out, $want, $label);
    return $ll;
}

# R3 corpus shape: literal replace, first match.
subtest 's/foo/baz/ on "foobar" => "bazbar"' => sub {
    my $ll = try_subst('foobar', 'foo', 'baz', 'Str:bazbar',
        's/foo/baz/ replaces the first match');
    return unless defined $ll;
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'substitution .ll is libperl-free');
};

subtest 's/// non-match leaves the subject unchanged' => sub {
    try_subst('foobar', 'xyz', 'baz', 'Str:foobar',
        's/xyz/baz/ does not change "foobar"');
};

subtest 's/// with different lengths (grow and shrink)' => sub {
    try_subst('ab',    'b',   'XYZ', 'Str:aXYZ', 'replacement longer than match');
    try_subst('aXYZb', 'XYZ', '',    'Str:ab',   'empty replacement deletes the match');
};

subtest 's/// replaces only the FIRST match (no /g)' => sub {
    try_subst('aXaXa', 'X', 'o', 'Str:aoaXa', 'only the first X is replaced');
};

subtest 's/(o+)/[$1]/ — explicit capture consumed in the replacement' => sub {
    try_subst('foobar', '(o+)', '[$1]', 'Str:f[oo]bar',
        '$1 in the replacement is the captured run');
};

subtest 's/(\\w+)-(\\w+)/$2_$1/ — two captures, reordered' => sub {
    try_subst('ab-cd', '(\\w+)-(\\w+)', '$2_$1', 'Str:cd_ab',
        '$2 and $1 reorder the halves');
};

done_testing;
