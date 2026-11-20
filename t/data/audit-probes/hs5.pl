my %h = (a => 1, b => 2); my $i = 0; while (%h) { delete $h{ (sort keys %h)[0] }; $i++ } print "$i\n";
