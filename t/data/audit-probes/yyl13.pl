my $s = "aaa"; (my $t = $s) =~ s/a/b/; my $u = $s =~ s/a/b/gr; my $c = ($s =~ s/a/c/g); my $z = ($s =~ s/z/y/); print "$s$t$u$c", $z eq "" ? "E" : "N", "\n";
