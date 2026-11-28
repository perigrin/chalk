my @a = (1,2); sub ad { push @a, @_ } my $n = @a; ad(3); print $n, scalar(@a), "\n";
