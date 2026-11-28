sub k { my $r = \$_[0]; sub { $$r } } my @c; for my $i (1..3) { my $x = $i; push @c, k($x) } print join(",", map { $_->() } @c), "\n";
