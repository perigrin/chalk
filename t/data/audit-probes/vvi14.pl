my $s = "hello"; my $c = ($s =~ tr/l/L/); my $r = $s =~ tr/L/l/r; print "$c$r$s\n";
