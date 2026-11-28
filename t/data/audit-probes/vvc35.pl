our $x = 1; my ($p, $q) = (3, 4); my $c = 0; *x = $c ? \$p : \$q; $x = 0; print "$p$q\n";
