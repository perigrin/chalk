my @a = (1,2,3); sub tot { my $t = 0; $t += $_ for @a; $t } my $s = ""; for my $e (@a) { $e *= 2; $s .= tot() . "," } print "$s\n";
