my $s = "abc"; my $t = $s =~ tr/b//dr; $s =~ tr/a//d; print "$s$t\n";
