sub inc { $_[0]++ } my $s="15"; inc(substr($s,1,1)); my @a=(1,2); inc($a[$#a]); inc($#{[1]}); print "$s@a\n";
