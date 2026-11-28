my @c; for my $i (1..2) { for my $j (1..2) { push @c, sub { "$i$j" } } } print join(",", map { $_->() } @c), "\n";
