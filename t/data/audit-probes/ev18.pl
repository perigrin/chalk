my $i = 0; while ($i < 5) { $i++; eval { next if $i == 2; 1 }; } print "$i\n";
