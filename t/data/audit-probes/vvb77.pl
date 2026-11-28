my @c; OUT: for my $i (1..3) { for my $j (1..3) { next OUT if $j > $i; my $x = "$i$j"; push @c, sub { $x } } } print join(",", map { $_->() } @c), "\n";
