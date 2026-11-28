my $s = "aaa"; my $n = $s =~ s/a/b/; my $m = $s =~ s/a/b/g; my $z = $s =~ s/z/y/; print "$n$m", $z eq "" ? "e" : "x", "$s\n";
