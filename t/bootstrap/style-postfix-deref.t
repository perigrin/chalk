# ABOUTME: lib/ code dereferences postfix ($r->@*, ->@[...], ->$#*), never @{ $r }:
# ABOUTME: CLAUDE.md's rule, and the form chalk's own Perl grammar recognizes.
use 5.42.0;
use Test::More;
use File::Find;

# Context.pm is being phased out (T2 replaces it); it is not rewritten.
my %EXEMPT = map { $_ => 1 } qw(lib/Chalk/Target/LLVM/Context.pm);

my @files;
find(sub { push @files, $File::Find::name if /\.pm\z/ }, 'lib');

for my $file (sort grep { !$EXEMPT{$_} } @files) {
    open my $fh, '<:utf8', $file or die "$file: $!";
    my @bad;
    while (my $line = <$fh>) {
        next if $line =~ /^\s*#/;
        ( my $code = $line ) =~ s/"(?:[^"\\]|\\.)*"//g;    # interpolation is not code
        $code =~ s/'(?:[^'\\]|\\.)*'//g;
        $code =~ s/\s#.*//;
        push @bad, "$.: $line" if $code =~ /(?:[\@%]|\$#)\{\s*\$/;
    }
    ok(!@bad, "$file: postfix dereference only") or diag @bad;
}

done_testing;
