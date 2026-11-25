my @a=(undef); for my $x (@a) { push @$x, 1 } print scalar(@{$a[0]}), "\n";
