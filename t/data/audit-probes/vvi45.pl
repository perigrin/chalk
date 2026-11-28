my $s = "abc"; (substr($s, 0, 1), substr($s, 2, 1)) = ("X", "Y"); print "$s\n";
