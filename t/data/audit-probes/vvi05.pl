my $s = "abc"; (my $t = $s) =~ s/b/z/; $s =~ s/a/q/; print "$s$t\n";
