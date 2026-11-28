my @c; my $i = 0; { my $x = $i++; push @c, sub { $x }; redo if $i < 3 } print join(",", map { $_->() } @c), "\n";
