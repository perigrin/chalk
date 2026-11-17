# ABOUTME: every string constant in T2's runtime is declared the size of its bytes:
# a miscounted one is an lli type error in every program that links it.
use 5.42.0;
use Test::More;

use lib 'lib';
use Chalk::Target::LLVM::Runtime;

# The .ll text itself, not Runtime.pm's source: the source quotes it, so its
# escapes (\') are not bytes of the constants.
my $src = Chalk::Target::LLVM::Runtime::prelude();
my $n = 0;
while ($src =~ /(\@\w+) = private unnamed_addr constant \[(\d+) x i8\] c"((?:[^"\\]|\\.)*)"/g) {
    my ($name, $declared, $c) = ($1, $2, $3);
    ( my $bytes = $c ) =~ s/\\([0-9A-Fa-f]{2})/chr hex $1/ge;
    is(length $bytes, $declared, "$name is [$declared x i8]");
    $n++;
}
ok($n > 10, "found the runtime's constants ($n)");
done_testing;
