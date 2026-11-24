my $s="ab"; (my $t = $s) =~ s/a/b/; ($s) = ($s =~ /(b)/); print "$s$t\n";
