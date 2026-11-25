my $s = "Hello, World"; (my $rot = $s) =~ tr/a-zA-Z/n-za-mN-ZA-M/; my $up = ($s =~ tr/A-Z//); my $c = ($s =~ tr/a-zA-Z//c); (my $d = $s) =~ tr/a-zA-Z//cd; print "$rot $up$c$d\n";
