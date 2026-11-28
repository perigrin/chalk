# The towers of Hanoi, from Opal's author/TESTING.md (stevan/pp): the
# moves printed, then played out on three pegs held as arrays, checked
# move by move.
use v5.42;

sub hanoi ($n, $source, $target, $aux) {
    if ($n > 0) {
        hanoi($n-1, $source, $aux, $target);
        say "Move disk $n from $source to $target";
        hanoi($n-1, $aux, $target, $source);
    }
}

hanoi(3, "A", "C", "B");

my %pegs = (A => [], B => [], C => []);
my @moves;

sub plan ($n, $from, $to, $via) {
    return if $n == 0;
    plan($n - 1, $from, $via, $to);
    push @moves, [$from, $to];
    plan($n - 1, $via, $to, $from);
}

sub show () {
    return join("  ", map { "$_: " . join(",", $pegs{$_}->@*) } sort keys %pegs);
}

my $disks = 5;
$pegs{A} = [reverse 1 .. $disks];
plan($disks, "A", "C", "B");
say "$disks disks take ", scalar(@moves), " moves (2**$disks - 1 = ", 2 ** $disks - 1, ")";
say "start   ", show();
my $step = 0;
for my $move (@moves) {
    my ($from, $to) = $move->@*;
    my $disk = pop $pegs{$from}->@*;
    die "no disk on $from\n" unless defined $disk;
    my $top = $pegs{$to}[-1];
    die "disk $disk onto smaller $top\n" if defined $top && $top < $disk;
    push $pegs{$to}->@*, $disk;
    $step++;
    say sprintf("%-7s ", "move $step"), show() if $step <= 6 || $step == @moves;
}
say "done: C holds ", join(" ", $pegs{C}->@*);
