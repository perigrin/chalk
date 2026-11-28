# Word frequency over a heredoc: words counted in a hash, sorted by
# count and then by word, with a bar chart and the longest words.
use v5.42;

my $text = <<~'END';
    It was the best of times, it was the worst of times,
    it was the age of wisdom, it was the age of foolishness,
    it was the epoch of belief, it was the epoch of incredulity,
    it was the season of Light, it was the season of Darkness,
    it was the spring of hope, it was the winter of despair,
    we had everything before us, we had nothing before us,
    we were all going direct to Heaven, we were all going direct
    the other way.
    END

my %count;
my $total = 0;
# No split and no regexes yet (steps 19 and 20): the words are cut out
# character by character.
sub words ($s) {
    my @words;
    my $word = "";
    for my $i (0 .. length($s) - 1) {
        my $ch = substr($s, $i, 1);
        if ($ch ge "a" && $ch le "z") {
            $word .= $ch;
        } elsif ($word ne "") {
            push @words, $word;
            $word = "";
        }
    }
    push @words, $word if $word ne "";
    return @words;
}

for my $word (words(lc $text)) {
    $count{$word}++;
    $total++;
}

my @by_count = sort { $count{$b} <=> $count{$a} or $a cmp $b } keys %count;
printf "%d words, %d different\n", $total, scalar(keys %count);
for my $w (@by_count[0 .. 9]) {
    printf "%-8s %3d %s\n", $w, $count{$w}, '#' x $count{$w};
}

my @once = grep { $count{$_} == 1 } sort keys %count;
say scalar(@once), " words appear once: @once[0 .. 5] ...";

my ($longest) = sort { length($b) <=> length($a) || $a cmp $b } keys %count;
say "the longest word is '$longest'";

my %by_len;
push @{ $by_len{length $_} }, $_ for sort keys %count;
for my $len (sort { $a <=> $b } keys %by_len) {
    say "$len: ", join(" ", sort @{ $by_len{$len} });
}
