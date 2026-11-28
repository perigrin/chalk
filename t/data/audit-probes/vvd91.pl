my %h; my ($x, $y) = @h{qw(a b)} = (1, 2, 3); print "$x$y", scalar(keys %h), "\n";
