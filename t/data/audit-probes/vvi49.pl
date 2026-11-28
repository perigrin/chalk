my $s = "abc"; my $t = join("", $s, $s =~ s/b/z/r, $s); print "$t\n";
