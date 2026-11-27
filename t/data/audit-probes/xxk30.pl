my $s = "hello"; substr($s, 0, 1) = "J"; substr($s, -1) =~ s/o/y/; my $t = substr($s, 1, 3, "EL"); print "$s$t\n";
