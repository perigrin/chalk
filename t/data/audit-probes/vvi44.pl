my $s = "abc"; substr($s, 1, 1) = substr($s, 0, 1); print "$s\n";
