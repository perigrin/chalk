# A stack and a queue made of closures over a private array, a counter
# factory, and an undo log, all held as hashes of code references.
use v5.42;

sub make_stack () {
    my @items;
    return {
        push  => sub ($x) { push @items, $x; return scalar(@items) },
        pop   => sub () { die "stack empty\n" unless @items; return pop @items },
        peek  => sub () { return $items[-1] },
        size  => sub () { return scalar(@items) },
        list  => sub () { return @items },
    };
}

sub make_queue () {
    my @items;
    my $served = 0;
    return {
        put   => sub (@xs) { push @items, @xs; return },
        take  => sub () {
            die "queue empty\n" unless @items;
            $served++;
            return shift @items;
        },
        size   => sub () { scalar(@items) },
        served => sub () { $served },
    };
}

sub make_counter ($start = 0, $step = 1) {
    my $n = $start;
    return sub { my $was = $n; $n += $step; return $was };
}

my $s = make_stack();
$s->{push}->($_) for qw(a b c d);
say "stack holds ", join(",", $s->{list}->()), "; size ", $s->{size}->();
say "popped ", $s->{pop}->(), ", then ", $s->{pop}->();
say "peek: ", $s->{peek}->();
$s->{pop}->() for 1 .. 2;
my $err;
try {
    $s->{pop}->();
} catch ($e) {
    $err = $e;
}
print "popping an empty stack: $err";

my $q = make_queue();
$q->{put}->(1 .. 5);
$q->{put}->("six");
my @got;
push @got, $q->{take}->() while $q->{size}->() > 2;
say "took @got; ", $q->{size}->(), " left; served ", $q->{served}->();

my $c1 = make_counter();
my $c2 = make_counter(100, -10);
say join(" ", map { $c1->() } 1 .. 5);
say join(" ", map { $c2->() } 1 .. 5);
say "c1 goes on at ", $c1->();

# Two stacks share nothing
my $t = make_stack();
$t->{push}->("x");
say "s has ", $s->{size}->(), ", t has ", $t->{size}->();

# An undo log: each change pushes a closure that reverses it
my %doc = (title => "draft", words => 100);
my @undo;
sub set_field ($k, $v) {
    my $old = $doc{$k};
    push @undo, sub { $doc{$k} = $old };
    $doc{$k} = $v;
}
set_field(title => "final");
set_field(words => 250);
set_field(title => "published");
say join(", ", map { "$_=$doc{$_}" } sort keys %doc);
while (@undo) {
    my $u = pop @undo;
    $u->();
    say "undo: ", join(", ", map { "$_=$doc{$_}" } sort keys %doc);
}
