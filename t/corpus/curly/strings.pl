# String manipulation with substr, index and friends: palindromes,
# a Caesar cipher, centring and wrapping text, counting a substring,
# replacing every occurrence, and title case.
use v5.42;

sub is_palindrome ($s) {
    my $clean = join "", grep { ($_ ge "a" && $_ le "z") || ($_ ge "0" && $_ le "9") } chars(lc $s);
    return $clean eq join("", reverse chars($clean));
}

# No split yet (step 20): a string's characters.
sub chars ($s) {
    return map { substr($s, $_, 1) } 0 .. length($s) - 1;
}

# No split on blanks either: the words of a string.
sub words ($s) {
    my @w;
    my $word = "";
    for my $c (chars($s), " ") {
        if ($c ne " ") {
            $word .= $c;
        } elsif (length $word) {
            push @w, $word;
            $word = "";
        }
    }
    return @w;
}

sub caesar ($s, $shift) {
    my $out = "";
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        if ($c ge "a" && $c le "z") {
            $c = chr((ord($c) - ord("a") + $shift) % 26 + ord("a"));
        } elsif ($c ge "A" && $c le "Z") {
            $c = chr((ord($c) - ord("A") + $shift) % 26 + ord("A"));
        }
        $out .= $c;
    }
    return $out;
}

sub centre ($s, $width) {
    my $room = $width - length $s;
    my $left = ($room - $room % 2) / 2;
    return " " x $left . $s . " " x ($width - length($s) - $left);
}

sub wrap ($text, $width) {
    my @lines;
    my $line = "";
    for my $word (words($text)) {
        if (length($line) + length($word) + 1 > $width && length $line) {
            push @lines, $line;
            $line = $word;
        } else {
            $line = length($line) ? "$line $word" : $word;
        }
    }
    push @lines, $line if length $line;
    return @lines;
}

sub count_of ($haystack, $needle) {
    my ($n, $pos) = (0, 0);
    while ((my $at = index($haystack, $needle, $pos)) >= 0) {
        $n++;
        $pos = $at + length $needle;
    }
    return $n;
}

sub replace_all ($s, $from, $to) {
    my $out = "";
    my $pos = 0;
    while ((my $at = index($s, $from, $pos)) >= 0) {
        $out .= substr($s, $pos, $at - $pos) . $to;
        $pos = $at + length $from;
    }
    return $out . substr($s, $pos);
}

sub title_case ($s) {
    return join " ", map { ucfirst lc $_ } words($s);
}

for my $s ("A man, a plan, a canal: Panama", "Never odd or even", "Curly", "") {
    printf "%-32s %s\n", "'$s'", is_palindrome($s) ? "palindrome" : "not";
}

my $secret = caesar("The Quick Brown Fox Jumps Over The Lazy Dog!", 13);
say $secret;
say caesar($secret, 13);
say caesar("abc xyz", 3), " / ", caesar(caesar("abc xyz", 3), 23);

say "[", centre("title", 21), "]";
say "[", centre("a longer title", 21), "]";

my $text = "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.";
say "|$_|" for wrap($text, 30);

say "'in' occurs ", count_of($text, "in"), " times; 'a ' ", count_of($text, "a "), " times";
say replace_all("the cat sat on the mat", "at", "og");
say title_case("the WIND in the willows");
say "last 'a' at ", rindex($text, "a"), ", first 'man' at ", index($text, "man");
say join("|", map { sprintf "%-6s", $_ } qw(left col), sprintf("%6s", "right"));
