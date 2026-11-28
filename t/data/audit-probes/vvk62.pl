my @a = ("a", "b"); my $s = ""; for (@a) { $s .= $_; s/a/c/; $s .= $_ } print "$s@a\n";
