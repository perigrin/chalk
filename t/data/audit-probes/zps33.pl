my $n=0; my $inc=sub { $n++ }; for (1..3) { $inc->() } print "$n\n";
