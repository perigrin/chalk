my $s = "a"; $s = "b" . $s; $s = "$s$s" if 1; print "$s\n";
