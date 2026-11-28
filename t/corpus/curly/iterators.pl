# Iterators and generators made of closures: ranges, map, filter, take,
# zip and chain over them, an infinite stream of primes, and function
# composition and currying.
use v5.42;

sub upto ($from, $to = undef) {
    my $n = $from;
    return sub { return undef if defined $to && $n > $to; return $n++ };
}

sub imap ($f, $it) {
    return sub { my $x = $it->(); return defined $x ? $f->($x) : undef };
}

sub igrep ($pred, $it) {
    return sub {
        while (defined(my $x = $it->())) {
            return $x if $pred->($x);
        }
        return undef;
    };
}

sub take ($n, $it) {
    my @out;
    while ($n-- > 0) {
        my $x = $it->();
        last unless defined $x;
        push @out, $x;
    }
    return @out;
}

sub zip_with ($f, $i, $j) {
    return sub {
        my ($x, $y) = ($i->(), $j->());
        return defined $x && defined $y ? $f->($x, $y) : undef;
    };
}

sub chain (@its) {
    return sub {
        while (@its) {
            my $x = $its[0]->();
            return $x if defined $x;
            shift @its;
        }
        return undef;
    };
}

sub primes () {
    my @found;
    return igrep(sub ($n) {
        for my $p (@found) {
            last if $p * $p > $n;
            return 0 if $n % $p == 0;
        }
        push @found, $n;
        return 1;
    }, upto(2));
}

sub compose (@fs) {
    return sub ($x) { $x = $_->($x) for reverse @fs; return $x };
}

sub curry ($f, @first) {
    return sub (@rest) { $f->(@first, @rest) };
}

say "1 to 10: ", join(" ", take(20, upto(1, 10)));
say "squares: ", join(" ", take(8, imap(sub ($x) { $x * $x }, upto(1))));
say "odd squares: ", join(" ", take(6, igrep(sub ($x) { $x % 2 }, imap(sub ($x) { $x * $x }, upto(1)))));
say "primes: ", join(" ", take(15, primes()));
say "pairs: ", join(" ", take(5, zip_with(sub ($x, $y) { "$x$y" }, upto(1), imap(sub ($n) { chr(96 + $n) }, upto(1)))));
say "chained: ", join(" ", take(10, chain(upto(1, 3), upto(10, 12), upto(100))));

my $inc = sub ($x) { $x + 1 };
my $dbl = sub ($x) { $x * 2 };
my $f = compose($dbl, $inc);
my $g = compose($inc, $dbl);
say "double after increment of 5: ", $f->(5), "; increment after double: ", $g->(5);

my $add3 = curry(sub ($x, $y, $z) { $x + $y + $z }, 1, 2);
say "curried: ", $add3->(10), " ", $add3->(20);

my $p = primes();
my @twins;
my $last = $p->();
while (@twins < 6) {
    my $next = $p->();
    push @twins, "$last/$next" if $next - $last == 2;
    $last = $next;
}
say "twin primes: @twins";
