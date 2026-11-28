my @a = (1); my $r = \$a[0]; my $q = \$a[0]; print $r == $q ? "same" : "diff", "\n";
