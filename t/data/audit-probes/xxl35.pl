my @s = (1); my $n = 0; while (defined(my $t = pop @s)) { $n += $t; push @s, $t + 1, $t + 2 if $t < 3 } print "$n\n";
