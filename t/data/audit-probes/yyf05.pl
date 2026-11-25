my @a=(undef); for my $x (@a) { for my $y (@$x) { } } print defined $a[0] ? "d" : "u", "\n";
