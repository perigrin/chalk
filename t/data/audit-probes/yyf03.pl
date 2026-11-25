my @a=(undef); for my $x (@a) { $x->[0]++ } print ref($a[0]), $a[0][0], "\n";
