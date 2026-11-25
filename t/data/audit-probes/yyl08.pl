my $s = "aXbXc"; $s =~ /X/g; my $p1 = pos($s); $s =~ /X/g; my $p2 = pos($s); $s =~ /X/g; print "$p1$p2", defined pos($s) ? "d" : "u", "\n";
