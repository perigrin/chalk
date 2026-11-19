my $x = 1; my $y = eval { my $t = $x + 1; die "x\n" if $t > 5; $t } // "u"; print "$y\n";
