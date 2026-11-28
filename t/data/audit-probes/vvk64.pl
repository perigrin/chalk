my $s = ""; for (1..3) { $s .= $_; next if $_ == 2; $s .= "-" } print "$s\n";
